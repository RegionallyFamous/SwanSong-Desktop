#!/usr/bin/env python3
"""Exercise exact-byte signing using a deterministic test-only Ed25519 seed."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "tools" / "catalog-signer"
TEST_SEED = bytes.fromhex(
    "9d61b19deffd5a60ba844af492ec2cc4"
    "4449c5697b326919703bac031cae7f60"
)


def run(binary: Path, *arguments: str, succeeds: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [str(binary), *arguments],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if (result.returncode == 0) != succeeds:
        raise AssertionError(
            f"unexpected signer status {result.returncode}: {result.stdout}{result.stderr}"
        )
    return result


def main() -> int:
    subprocess.run(
        ["swift", "build", "--package-path", str(PACKAGE), "-c", "release"],
        cwd=ROOT,
        check=True,
    )
    bin_path = subprocess.run(
        ["swift", "build", "--package-path", str(PACKAGE), "-c", "release", "--show-bin-path"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        check=True,
    ).stdout.strip()
    binary = Path(bin_path) / "catalog-signer"

    with tempfile.TemporaryDirectory(prefix="swansong-catalog-signer-") as temporary:
        root = Path(temporary)
        catalog = root / "catalog-v1.json"
        changed = root / "changed.json"
        private_key = root / "test-only.private.b64"
        public_key = root / "public.json"
        signature = root / "catalog-v1.sig.json"
        exact = b'{"schemaVersion":1,"revision":1}\n'
        catalog.write_bytes(exact)
        private_key.write_text(base64.b64encode(TEST_SEED).decode("ascii") + "\n")
        os.chmod(private_key, 0o600)

        exported = run(
            binary,
            "export-public",
            "--private-key",
            str(private_key),
            "--public-key",
            str(public_key),
        )
        key_id = exported.stdout.strip()
        assert key_id.startswith("ed25519-") and len(key_id) == 24

        run(
            binary,
            "sign",
            "--catalog",
            str(catalog),
            "--output",
            str(signature),
            "--signing-key",
            f"{key_id}={private_key}",
        )
        run(
            binary,
            "verify",
            "--catalog",
            str(catalog),
            "--signature",
            str(signature),
            "--public-key",
            str(public_key),
        )

        envelope = json.loads(signature.read_text())
        assert envelope["catalogByteCount"] == len(exact)
        assert envelope["catalogSHA256"] == hashlib.sha256(exact).hexdigest()
        assert envelope["signatures"][0]["keyID"] == key_id

        changed.write_bytes(exact + b" ")
        run(
            binary,
            "verify",
            "--catalog",
            str(changed),
            "--signature",
            str(signature),
            "--public-key",
            str(public_key),
            succeeds=False,
        )
        os.chmod(private_key, 0o644)
        run(
            binary,
            "sign",
            "--catalog",
            str(catalog),
            "--output",
            str(signature),
            "--signing-key",
            f"{key_id}={private_key}",
            succeeds=False,
        )

    print("catalog signer self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
