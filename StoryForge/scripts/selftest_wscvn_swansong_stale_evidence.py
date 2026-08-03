#!/usr/bin/env python3
from __future__ import annotations

import tempfile
from pathlib import Path

from playtest_wscvn_swansong import quarantine_stale_route_evidence


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="wscvn-swansong-stale-") as temp_dir:
        root = Path(temp_dir)
        evidence = root / "assets" / "swansong-playthrough"
        report = root / "reports" / "swansong-playthrough-report.json"
        evidence.mkdir(parents=True)
        report.parent.mkdir(parents=True)

        stale_names = {
            "route-1-ending.png",
            "route-1-audio.wav",
            "route-27-stall.png",
        }
        for name in stale_names:
            (evidence / name).write_bytes(name.encode("utf-8"))
        keep = evidence / "reviewed-ending.png"
        keep.write_bytes(b"keep")

        moved, quarantine = quarantine_stale_route_evidence(evidence, report)
        assert set(moved) == stale_names
        assert quarantine is not None and quarantine.is_dir()
        assert keep.read_bytes() == b"keep"
        for name in stale_names:
            assert not (evidence / name).exists()
            assert (quarantine / name).read_bytes() == name.encode("utf-8")

        moved_again, quarantine_again = quarantine_stale_route_evidence(evidence, report)
        assert moved_again == []
        assert quarantine_again is None

    print("SwanSong stale-evidence quarantine self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
