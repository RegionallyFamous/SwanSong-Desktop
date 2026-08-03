#!/usr/bin/env python3
"""Invoke the first-party CryptoKit catalog signer without reading private bytes."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "tools" / "catalog-signer"
DEFAULT_CATALOG = ROOT / "distribution" / "catalog-v1.json"
DEFAULT_SIGNATURE = ROOT / "distribution" / "catalog-v1.sig.json"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    sign_parser = subparsers.add_parser("sign", help="sign exact catalog bytes")
    sign_parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    sign_parser.add_argument("--output", type=Path, default=DEFAULT_SIGNATURE)
    sign_parser.add_argument(
        "--signing-key",
        action="append",
        required=True,
        metavar="KEY_ID=PRIVATE_KEY_PATH",
        help="repeat for a dual-signing rotation",
    )

    verify_parser = subparsers.add_parser("verify", help="verify a detached signature")
    verify_parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    verify_parser.add_argument("--signature", type=Path, default=DEFAULT_SIGNATURE)
    verify_parser.add_argument(
        "--public-key",
        action="append",
        required=True,
        type=Path,
        help="repeat for multiple trusted public-key documents",
    )

    args = parser.parse_args()
    command = [
        "swift",
        "run",
        "--package-path",
        str(PACKAGE),
        "-c",
        "release",
        "catalog-signer",
        args.command,
        "--catalog",
        str(args.catalog.resolve()),
    ]
    if args.command == "sign":
        command.extend(["--output", str(args.output.resolve())])
        for key in args.signing_key:
            command.extend(["--signing-key", key])
    else:
        command.extend(["--signature", str(args.signature.resolve())])
        for public_key in args.public_key:
            command.extend(["--public-key", str(public_key.resolve())])
    return subprocess.run(command, cwd=ROOT, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
