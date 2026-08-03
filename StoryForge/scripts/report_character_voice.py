#!/usr/bin/env python3
from __future__ import annotations

import runpy
from pathlib import Path


TARGET = Path(__file__).resolve().parents[1] / "skills" / "forge-light-novels" / "scripts" / "report_character_voice.py"
runpy.run_path(str(TARGET), run_name="__main__")
