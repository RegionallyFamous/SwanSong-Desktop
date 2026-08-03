#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


SCRIPT_ROOT = Path(__file__).resolve().parents[1] / "skills" / "forge-light-novels" / "scripts"
sys.path.insert(0, str(SCRIPT_ROOT))
from wscvn_story_proof import build_story_proof


def main() -> int:
    parser = argparse.ArgumentParser(description="Prove authored story beats against exhaustive SwanSong runtime evidence.")
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--playthrough", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--html", type=Path, required=True)
    parser.add_argument("--json", action="store_true", help="Print the complete report instead of a concise summary.")
    args = parser.parse_args()
    try:
        payload = build_story_proof(args.contract, args.project, args.playthrough, report_path=args.out, html_path=args.html)
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        payload = {"schema": "wscvn-story-proof-report-v1", "ok": False, "errors": [str(exc)], "warnings": []}
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    if args.json:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        coverage = payload.get("coverage") or {}
        print(
            "Story Proof: "
            f"{'passed' if payload.get('ok') else 'NEEDS ATTENTION'}; "
            f"checkpoints={coverage.get('checkpoints_proven', 0)}/{coverage.get('checkpoints_declared', 0)}; "
            f"routes={coverage.get('routes_proven', 0)}/{coverage.get('routes_executed', 0)}"
        )
        for error in (payload.get("errors") or [])[:8]:
            print(f"[x] {error}")
    return 0 if payload.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
