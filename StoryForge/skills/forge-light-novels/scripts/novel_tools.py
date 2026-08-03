#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCENE_MARKER_RE = re.compile(r"<!--\s*scene:\s*([a-z0-9]+(?:-[a-z0-9]+)*)\s*-->", re.IGNORECASE)
VOICE_MARKER_RE = re.compile(r"<!--\s*voice:\s*([a-z0-9]+(?:-[a-z0-9]+)*)\s*-->", re.IGNORECASE)
WORD_RE = re.compile(r"[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)*")
SENTENCE_RE = re.compile(r"(?<=[.!?])(?:[\"'”’)]*)\s+")
PLACEHOLDER_RE = re.compile(r"(?:\bTODO\b|\bTBD\b|\bLOREM\b|__[A-Z0-9_]+__)", re.IGNORECASE)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_manifest(path: Path) -> dict[str, Any]:
    path = path.expanduser().resolve()
    if path.suffix.lower() == ".json":
        value = json.loads(path.read_text(encoding="utf-8"))
    elif path.suffix.lower() in {".yaml", ".yml"}:
        try:
            import yaml  # type: ignore
            value = yaml.safe_load(path.read_text(encoding="utf-8"))
        except ModuleNotFoundError:
            value = None
            code = (
                "import json,sys,yaml; "
                "json.dump(yaml.safe_load(open(sys.argv[1], encoding='utf-8')), sys.stdout, ensure_ascii=False)"
            )
            for candidate in (Path("/usr/bin/python3"), Path("/opt/homebrew/bin/python3")):
                if not candidate.is_file() or str(candidate.resolve()) == str(Path(sys.executable).resolve()):
                    continue
                result = subprocess.run(
                    [str(candidate), "-c", code, str(path)],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False,
                )
                if result.returncode == 0:
                    value = json.loads(result.stdout)
                    break
            if value is None:
                raise RuntimeError("YAML input requires PyYAML in an available Python interpreter")
    else:
        raise RuntimeError("Manifest must end in .json, .yaml, or .yml")
    if not isinstance(value, dict):
        raise RuntimeError("Manifest root must be an object")
    return value


def project_path(root: Path, value: str) -> Path:
    path = (root / value).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError as exc:
        raise RuntimeError(f"Project path escapes its root: {value}") from exc
    return path


def manuscript_files(manifest_path: Path, manifest: dict[str, Any]) -> list[Path]:
    root = manifest_path.expanduser().resolve().parent
    directory = project_path(root, str((manifest.get("manuscript") or {}).get("directory") or "manuscript"))
    if not directory.is_dir():
        raise RuntimeError(f"Manuscript directory is missing: {directory}")
    files = sorted(directory.glob("*.md"))
    if not files:
        raise RuntimeError(f"No Markdown manuscript files found in {directory}")
    return files


def manuscript_sha256(files: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in sorted(files):
        digest.update(path.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def manuscript_sections(files: list[Path]) -> tuple[dict[str, str], list[str]]:
    combined = "\n".join(path.read_text(encoding="utf-8") for path in files)
    matches = list(SCENE_MARKER_RE.finditer(combined))
    sections: dict[str, str] = {}
    order: list[str] = []
    for index, match in enumerate(matches):
        scene_id = match.group(1).lower()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(combined)
        sections[scene_id] = combined[match.end() : end].strip()
        order.append(scene_id)
    return sections, order


def clean_markdown(text: str) -> str:
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.DOTALL)
    text = re.sub(r"```.*?```", " ", text, flags=re.DOTALL)
    text = re.sub(r"^[#>*_-]+\s*", "", text, flags=re.MULTILINE)
    text = re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"[*_`]+", "", text)
    return "\n".join(line.rstrip() for line in text.splitlines())


def words(text: str) -> list[str]:
    return WORD_RE.findall(clean_markdown(text))


def sentences(text: str) -> list[str]:
    return [item.strip() for item in SENTENCE_RE.split(clean_markdown(text)) if item.strip()]


def voice_samples(sections: dict[str, str]) -> dict[str, list[dict[str, str]]]:
    result: dict[str, list[dict[str, str]]] = {}
    for scene_id, body in sections.items():
        matches = list(VOICE_MARKER_RE.finditer(body))
        for index, match in enumerate(matches):
            end = matches[index + 1].start() if index + 1 < len(matches) else len(body)
            tail = body[match.end() : end].lstrip()
            paragraph = re.split(r"\n\s*\n", tail, maxsplit=1)[0]
            sample = " ".join(clean_markdown(paragraph).split())
            if sample:
                result.setdefault(match.group(1).lower(), []).append({"scene_id": scene_id, "text": sample})
    return result


def report_base(tool: str, manifest_path: Path, manifest: dict[str, Any], files: list[Path]) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "tool": tool,
        "manifest": {
            "path": str(manifest_path.resolve()),
            "sha256": sha256(manifest_path),
        },
        "manuscript_sha256": manuscript_sha256(files),
        "slug": (manifest.get("identity") or {}).get("slug"),
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def normalized_text(value: Any) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", str(value).lower()))


def asset_set_sha256(items: list[dict[str, Any]]) -> str:
    """Hash an ordered production-art set by stable id, path, and file bytes."""
    digest = hashlib.sha256()
    for item in sorted(items, key=lambda value: str(value.get("id") or "")):
        digest.update(str(item.get("id") or "").encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(item.get("asset_path") or "").encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(item.get("asset_sha256") or "").encode("ascii", errors="ignore"))
        digest.update(b"\0")
    return digest.hexdigest()
