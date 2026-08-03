#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

from smoke_wscvn_rom import smoke_rom


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "emulator-smoke-report.json"
DEFAULT_ROM = ROOT / "runtime-local" / "signal-before-dawn-slice.wsc"
DEFAULT_SCREENSHOT = ROOT / "assets" / "signal-before-dawn-slice" / "emulator-title-screen-v2.png"


def main() -> int:
    rom = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_ROM
    return smoke_rom(rom.expanduser().resolve(), REPORT, screenshot=DEFAULT_SCREENSHOT)


if __name__ == "__main__":
    raise SystemExit(main())
