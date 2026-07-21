#!/usr/bin/env python3
"""Find and verify SwanSong's Developer ID provisioning profiles."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path


def decode_profile(path: Path) -> dict:
    result = subprocess.run(
        ["security", "cms", "-D", "-i", str(path)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return plistlib.loads(result.stdout)


def validate_profile(
    profile: dict,
    *,
    name: str,
    application_identifier: str,
    app_group: str,
    minimum_days: int,
) -> None:
    if profile.get("Name") != name:
        raise ValueError(f"profile name is not {name!r}")

    entitlements = profile.get("Entitlements", {})
    if entitlements.get("com.apple.application-identifier") != application_identifier:
        raise ValueError("profile application identifier does not match")
    groups = entitlements.get("com.apple.security.application-groups", [])
    group_is_authorized = any(
        candidate == app_group
        or (
            candidate.endswith(".*")
            and app_group.startswith(candidate[:-1])
            and app_group.startswith(f"{application_identifier.split('.', 1)[0]}.")
        )
        for candidate in groups
    )
    if not group_is_authorized:
        raise ValueError("profile does not grant the SwanSong App Group")

    team_identifier = application_identifier.split(".", 1)[0]
    if team_identifier not in profile.get("TeamIdentifier", []):
        raise ValueError("profile team identifier does not match")
    if not profile.get("ProvisionsAllDevices", False):
        raise ValueError("profile is not a Developer ID all-device profile")
    if profile.get("ProvisionedDevices"):
        raise ValueError("profile is unexpectedly device-bound")
    if "OSX" not in profile.get("Platform", []):
        raise ValueError("profile is not valid for macOS")

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, dt.datetime):
        raise ValueError("profile has no valid expiration date")
    now = dt.datetime.now(dt.timezone.utc)
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=dt.timezone.utc)
    if expiration <= now + dt.timedelta(days=minimum_days):
        raise ValueError("profile expires too soon")


def candidate_paths(explicit: str | None) -> list[Path]:
    if explicit:
        return [Path(explicit).expanduser()]
    home = Path.home()
    roots = [
        home / "Library/Developer/Xcode/UserData/Provisioning Profiles",
        home / "Library/MobileDevice/Provisioning Profiles",
        home / "Downloads",
    ]
    paths: list[Path] = []
    for root in roots:
        if root.is_dir():
            paths.extend(root.glob("*.provisionprofile"))
            paths.extend(root.glob("*.mobileprovision"))
    return sorted(set(paths))


def find_profile(args: argparse.Namespace) -> int:
    matches: list[tuple[dt.datetime, Path]] = []
    failures: list[str] = []
    for path in candidate_paths(args.explicit):
        try:
            profile = decode_profile(path)
            validate_profile(
                profile,
                name=args.name,
                application_identifier=args.application_identifier,
                app_group=args.app_group,
                minimum_days=args.minimum_days,
            )
            matches.append((profile["ExpirationDate"], path.resolve()))
        except (OSError, subprocess.CalledProcessError, plistlib.InvalidFileException, ValueError) as error:
            if args.explicit:
                failures.append(f"{path}: {error}")

    if not matches:
        detail = "; ".join(failures) if failures else "no matching installed profile"
        print(detail, file=sys.stderr)
        return 1
    matches.sort(key=lambda item: (item[0], str(item[1])), reverse=True)
    print(matches[0][1])
    return 0


def extracted_leaf_certificate(bundle: Path) -> bytes:
    with tempfile.TemporaryDirectory(prefix="swansong-certificate-") as directory:
        prefix = Path(directory) / "certificate"
        subprocess.run(
            ["codesign", "-d", f"--extract-certificates={prefix}", str(bundle)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return Path(f"{prefix}0").read_bytes()


def verify_profile(args: argparse.Namespace) -> int:
    path = Path(args.profile)
    profile = decode_profile(path)
    validate_profile(
        profile,
        name=args.name,
        application_identifier=args.application_identifier,
        app_group=args.app_group,
        minimum_days=args.minimum_days,
    )
    leaf = extracted_leaf_certificate(Path(args.signed_bundle))
    allowed = [bytes(certificate) for certificate in profile.get("DeveloperCertificates", [])]
    if not allowed or leaf not in allowed:
        raise ValueError("profile does not contain the bundle's signing certificate")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f"PASS {args.name} profile is valid and bound to the signer ({digest})")
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    subparsers = result.add_subparsers(dest="command", required=True)
    for command in ("find", "verify"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--name", required=True)
        subparser.add_argument("--application-identifier", required=True)
        subparser.add_argument("--app-group", required=True)
        subparser.add_argument("--minimum-days", type=int, default=30)
        if command == "find":
            subparser.add_argument("--explicit")
        else:
            subparser.add_argument("--profile", required=True)
            subparser.add_argument("--signed-bundle", required=True)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "find":
            return find_profile(args)
        return verify_profile(args)
    except (OSError, subprocess.CalledProcessError, plistlib.InvalidFileException, ValueError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
