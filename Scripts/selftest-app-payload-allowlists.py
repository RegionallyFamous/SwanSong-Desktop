#!/usr/bin/env python3
"""Keep the build-time and release-time app payload allowlists aligned."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PATH_PATTERN = re.compile(r'! -path "\$APP([^\"]+)"')


def file_allowlist(path: Path, start: str, end: str) -> set[str]:
    source = path.read_text(encoding="utf-8")
    block = source[source.index(start) : source.index(end)]
    return set(PATH_PATTERN.findall(block))


def main() -> int:
    build_allowlist = file_allowlist(
        ROOT / "check-app-payload.sh",
        "unexpected_file=$(find",
        'if [ -n "$unexpected_file"',
    )
    release_allowlist = file_allowlist(
        ROOT / "verify-release-artifacts.sh",
        "UNEXPECTED_FILE=$(find",
        '[ -z "$UNEXPECTED_FILE"',
    )

    # CodeResources is a compatibility symlink after extraction, so the
    # release verifier names it defensively even though `find -type f` cannot
    # select it. Every regular-file exception must otherwise be identical.
    release_allowlist.discard("/Contents/CodeResources")
    if build_allowlist != release_allowlist:
        missing = sorted(build_allowlist - release_allowlist)
        extra = sorted(release_allowlist - build_allowlist)
        raise SystemExit(
            "app payload allowlists differ: "
            f"missing from release verifier={missing}; "
            f"release-only={extra}"
        )

    required_profiles = {
        "/Contents/embedded.provisionprofile",
        (
            "/Contents/XPCServices/SwanSongEngineService.xpc/Contents/"
            "embedded.provisionprofile"
        ),
    }
    if not required_profiles.issubset(release_allowlist):
        raise SystemExit("the signed App Group provisioning profiles are not allowlisted")

    print("PASS build and release app payload allowlists are synchronized")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
