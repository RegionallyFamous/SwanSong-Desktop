from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any


CONDITION_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(==|!=|>=|<=|>|<)\s*(-?\d+)\s*$")


@dataclass(frozen=True)
class RouteDecision:
    kind: str
    node_id: str
    label: str
    target: str
    source_index: int
    visible_index: int | None = None
    cursor_x: int | None = None
    cursor_y: int | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "kind": self.kind,
            "node_id": self.node_id,
            "label": self.label,
            "target": self.target,
            "source_index": self.source_index,
            "visible_index": self.visible_index,
            "cursor_x": self.cursor_x,
            "cursor_y": self.cursor_y,
        }


@dataclass(frozen=True)
class RoutePlan:
    route_index: int
    graph_nodes: tuple[str, ...]
    expected_nodes: tuple[str, ...]
    decisions: tuple[RouteDecision, ...]
    ending_node: str
    final_flags: tuple[tuple[str, int], ...]

    @property
    def route_id(self) -> str:
        return f"route-{self.route_index + 1}"

    @property
    def label(self) -> str:
        labels = [decision.label for decision in self.decisions]
        return " / ".join(labels) if labels else "Main route"

    def as_dict(self) -> dict[str, Any]:
        return {
            "route_index": self.route_index,
            "route_id": self.route_id,
            "label": self.label,
            "graph_nodes": list(self.graph_nodes),
            "expected_nodes": list(self.expected_nodes),
            "decisions": [decision.as_dict() for decision in self.decisions],
            "ending_node": self.ending_node,
            "final_flags": dict(self.final_flags),
        }


def _compare(value: int, operator: str, expected: int) -> bool:
    return {
        "==": value == expected,
        "!=": value != expected,
        ">=": value >= expected,
        "<=": value <= expected,
        ">": value > expected,
        "<": value < expected,
    }.get(operator, False)


def _initial_flags(project: dict[str, Any], errors: list[str]) -> dict[str, int]:
    result: dict[str, int] = {}
    for entry in project.get("flags") or []:
        name = str(entry.get("name") or "")
        if not name:
            errors.append("route planning found a flag without a name")
            continue
        try:
            result[name] = int(entry.get("initial", 0) or 0)
        except (TypeError, ValueError):
            errors.append(f"route planning found a non-numeric initial value for {name!r}")
            result[name] = 0
    return result


def _condition_matches(
    condition: str,
    flags: dict[str, int],
    errors: list[str],
    context: str,
) -> bool:
    if not condition.strip():
        return True
    match = CONDITION_RE.fullmatch(condition)
    if match is None:
        errors.append(f"{context} has unsupported condition {condition!r}")
        return False
    name, operator, raw_expected = match.groups()
    if name not in flags:
        errors.append(f"{context} references undefined flag {name!r}")
        return False
    return _compare(flags[name], operator, int(raw_expected))


def _branch_matches(
    branch: dict[str, Any],
    flags: dict[str, int],
    errors: list[str],
    context: str,
) -> bool:
    name = str(branch.get("flag") or "")
    operator = str(branch.get("op") or "==")
    if name not in flags:
        errors.append(f"{context} references undefined flag {name!r}")
        return False
    try:
        expected = int(branch.get("value", 0) or 0)
    except (TypeError, ValueError):
        errors.append(f"{context} has non-numeric branch value {branch.get('value')!r}")
        return False
    if operator not in {"==", "!=", ">=", "<=", ">", "<"}:
        errors.append(f"{context} has unsupported branch operator {operator!r}")
        return False
    return _compare(flags[name], operator, expected)


def _apply_ops(
    flags: dict[str, int],
    operations: list[dict[str, Any]],
    errors: list[str],
    context: str,
) -> dict[str, int]:
    result = dict(flags)
    for operation in operations:
        name = str(operation.get("name") or "")
        if not name:
            errors.append(f"{context} has a flag operation without a name")
            continue
        if name not in result:
            errors.append(f"{context} references undefined flag {name!r}")
            result[name] = 0
        try:
            value = int(operation.get("value", 0) or 0)
        except (TypeError, ValueError):
            errors.append(f"{context} has non-numeric flag value {operation.get('value')!r}")
            value = 0
        operator = str(operation.get("op") or "set")
        if operator == "set":
            result[name] = value
        elif operator == "add":
            result[name] += value
        elif operator == "sub":
            result[name] -= value
        elif operator == "toggle":
            result[name] = 0 if result[name] else 1
        elif operator in {"rand", "random"}:
            errors.append(
                f"{context} uses random flag operation {operator!r}; exhaustive compiled-route "
                "testing requires deterministic authoring or explicit seeded route fixtures"
            )
        else:
            errors.append(f"{context} has unsupported flag operation {operator!r}")
    return result


def _hotspot_cursor(hotspot: dict[str, Any]) -> tuple[int, int]:
    x = int(hotspot.get("x", 0) or 0)
    y = int(hotspot.get("y", 0) or 0)
    width = max(1, int(hotspot.get("w", 1) or 1))
    height = max(1, int(hotspot.get("h", 1) or 1))
    cursor_x = min(27, max(0, (x + width // 2) // 8))
    cursor_y = min(17, max(0, (y + height // 2) // 8))
    return cursor_x, cursor_y


def enumerate_route_plans(
    project: dict[str, Any],
    *,
    maximum_routes: int = 256,
    maximum_states: int = 20_000,
) -> tuple[list[RoutePlan], list[str]]:
    errors: list[str] = []
    nodes = project.get("nodes") or []
    by_id = {str(node.get("id")): node for node in nodes if node.get("id")}
    start = str(project.get("startNodeId") or "")
    if not start or start not in by_id:
        return [], [f"route planning cannot resolve startNodeId {start!r}"]

    initial_flags = _initial_flags(project, errors)
    # node, flags, path, decisions, exact states already visited on this path
    queue: list[
        tuple[
            str,
            dict[str, int],
            tuple[str, ...],
            tuple[RouteDecision, ...],
            frozenset[tuple[str, tuple[tuple[str, int], ...]]],
        ]
    ] = [(start, initial_flags, (), (), frozenset())]
    raw_plans: list[tuple[tuple[str, ...], tuple[RouteDecision, ...], str, tuple[tuple[str, int], ...]]] = []
    explored = 0

    while queue:
        if explored >= maximum_states:
            errors.append(f"route planning exceeded {maximum_states} path states")
            break
        node_id, flags, path, decisions, path_states = queue.pop(0)
        explored += 1
        node = by_id.get(node_id)
        if node is None:
            errors.append(f"route planning reached missing node {node_id!r}")
            continue

        node_flags = dict(flags)
        if node.get("type") == "scene":
            node_flags = _apply_ops(
                node_flags,
                node.get("sceneFlagOps") or [],
                errors,
                f"{node_id} scene",
            )
        flag_key = tuple(sorted(node_flags.items()))
        state = (node_id, flag_key)
        if state in path_states:
            errors.append(f"route planning found a cycle at {node_id!r} with unchanged flag state")
            continue
        next_states = path_states | {state}
        next_path = path + (node_id,)
        node_type = str(node.get("type") or "")

        if node_type == "end":
            raw_plans.append((next_path, decisions, node_id, flag_key))
            if len(raw_plans) > maximum_routes:
                errors.append(f"route planning exceeded {maximum_routes} complete routes")
                break
            continue

        if node_type == "choice":
            visible = [
                (source_index, choice)
                for source_index, choice in enumerate(node.get("choices") or [])
                if _condition_matches(
                    str(choice.get("condition") or ""),
                    node_flags,
                    errors,
                    f"{node_id} choice {choice.get('text')!r}",
                )
            ]
            if not visible:
                target = str(node.get("defaultTarget") or "")
                if target:
                    queue.append((target, node_flags, next_path, decisions, next_states))
                else:
                    errors.append(f"route planning found no visible choices or default at {node_id!r}")
                continue
            for visible_index, (source_index, choice) in enumerate(visible):
                target = str(choice.get("target") or "")
                if not target:
                    errors.append(f"{node_id} choice {source_index + 1} has no target")
                    continue
                changed_flags = _apply_ops(
                    node_flags,
                    choice.get("flagOps") or [],
                    errors,
                    f"{node_id} choice {choice.get('text')!r}",
                )
                decision = RouteDecision(
                    kind="choice",
                    node_id=node_id,
                    label=str(choice.get("text") or f"Choice {source_index + 1}"),
                    target=target,
                    source_index=source_index,
                    visible_index=visible_index,
                )
                queue.append(
                    (target, changed_flags, next_path, decisions + (decision,), next_states)
                )
            continue

        if node_type == "branch":
            target = ""
            for branch_index, branch in enumerate(node.get("branches") or []):
                if _branch_matches(branch, node_flags, errors, f"{node_id} branch {branch_index + 1}"):
                    target = str(branch.get("target") or "")
                    break
            if not target:
                target = str(node.get("defaultTarget") or "")
            if target:
                queue.append((target, node_flags, next_path, decisions, next_states))
            else:
                errors.append(f"route planning found no matching branch or default at {node_id!r}")
            continue

        if node_type == "investigation":
            produced = False
            for source_index, hotspot in enumerate(node.get("hotspots") or []):
                target = str(hotspot.get("target") or "")
                if not target:
                    continue
                cursor_x, cursor_y = _hotspot_cursor(hotspot)
                decision = RouteDecision(
                    kind="investigation",
                    node_id=node_id,
                    label=str(hotspot.get("label") or hotspot.get("text") or f"Hotspot {source_index + 1}"),
                    target=target,
                    source_index=source_index,
                    cursor_x=cursor_x,
                    cursor_y=cursor_y,
                )
                changed_flags = _apply_ops(
                    node_flags,
                    hotspot.get("flagOps") or [],
                    errors,
                    f"{node_id} hotspot {source_index + 1}",
                )
                queue.append(
                    (target, changed_flags, next_path, decisions + (decision,), next_states)
                )
                produced = True
            default_target = str(node.get("defaultTarget") or "")
            if default_target:
                decision = RouteDecision(
                    kind="investigation-default",
                    node_id=node_id,
                    label="Leave investigation",
                    target=default_target,
                    source_index=-1,
                )
                queue.append(
                    (default_target, node_flags, next_path, decisions + (decision,), next_states)
                )
                produced = True
            if not produced:
                errors.append(f"route planning found no reachable investigation exit at {node_id!r}")
            continue

        target = str(node.get("next") or node.get("defaultTarget") or "")
        if target:
            queue.append((target, node_flags, next_path, decisions, next_states))
        else:
            errors.append(f"route planning found dead end at {node_id!r}")

    unique: dict[
        tuple[tuple[str, ...], tuple[RouteDecision, ...]],
        tuple[tuple[str, ...], tuple[RouteDecision, ...], str, tuple[tuple[str, int], ...]],
    ] = {}
    for raw in raw_plans:
        unique[(raw[0], raw[1])] = raw
    plans = [
        RoutePlan(
            route_index=index,
            graph_nodes=raw[0],
            expected_nodes=tuple(
                node_id
                for node_id in raw[0]
                if str((by_id.get(node_id) or {}).get("type") or "")
                not in {"branch", "chapter"}
            ),
            decisions=raw[1],
            ending_node=raw[2],
            final_flags=raw[3],
        )
        for index, raw in enumerate(unique.values())
    ]
    if not plans:
        errors.append("route planning found no complete route to an end node")
    return plans, list(dict.fromkeys(errors))
