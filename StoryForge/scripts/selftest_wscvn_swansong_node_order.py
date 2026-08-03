#!/usr/bin/env python3
"""Prove SwanSong mailbox indices follow converter runtime node order."""

from __future__ import annotations

from playtest_wscvn_swansong import compiled_node_ids


def main() -> int:
    project = {
        "nodes": [
            {"id": "title", "type": "title", "next": "opening"},
            {"id": "opening", "type": "scene", "next": "choice"},
            {"id": "choice", "type": "choice", "choices": [
                {"target": "left"},
                {"target": "right"},
            ]},
            # This source order deliberately places the join before a choice
            # target, so the converter must move it after both branches.
            {"id": "join", "type": "scene", "next": "end"},
            {"id": "left", "type": "scene", "next": "left_detail"},
            {"id": "left_detail", "type": "scene", "next": "join"},
            {"id": "right", "type": "scene", "next": "join"},
            {"id": "end", "type": "end"},
        ]
    }
    actual = compiled_node_ids(project)
    expected = [
        "title", "opening", "choice", "left", "left_detail", "right", "join", "end"
    ]
    if actual != expected:
        print(f"compiled node order mismatch: expected {expected}, got {actual}")
        return 1
    if actual.index("choice") == project["nodes"].index(next(
        node for node in project["nodes"] if node["id"] == "choice"
    )) and actual.index("join") == 3:
        print("fixture did not exercise runtime reordering")
        return 1
    print("SwanSong compiled node-order self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
