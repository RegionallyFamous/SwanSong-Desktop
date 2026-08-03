#!/usr/bin/env python3
from __future__ import annotations

from check_wscvn_audio_proof import tracker_loop_seconds


def main() -> int:
    short = tracker_loop_seconds(bpm=58, length_steps=32)
    long = tracker_loop_seconds(bpm=58, length_steps=192)
    if abs(long - short * 6.0) > 1e-9:
        print("[x] a 192-step cue was not measured as six 32-step phrases")
        return 1
    if abs(long - 49.6551724137931) > 1e-9:
        print(f"[x] unexpected 192-step loop duration: {long}")
        return 1
    print("WSC VN audio-proof timing selftest: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
