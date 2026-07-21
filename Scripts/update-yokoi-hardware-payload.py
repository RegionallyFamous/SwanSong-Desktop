#!/usr/bin/env python3
"""Refresh Desktop's bounded Yokoi payload from a local SwanSong Core tree."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import shutil
import zlib


ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / "Packaging/YokoiHardware"


def read_regular(path: Path, maximum: int) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"missing or linked Yokoi input: {path}")
    data = path.read_bytes()
    if not 0 < len(data) <= maximum:
        raise SystemExit(f"invalid Yokoi input size: {path}")
    return data


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def encode(data: bytes) -> bytes:
    compressor = zlib.compressobj(level=9, wbits=-15)
    compressed = compressor.compress(data) + compressor.flush()
    value = base64.b64encode(compressed).decode("ascii")
    return ("\n".join(value[index:index + 76] for index in range(0, len(value), 76)) + "\n").encode()


def artifact(encoded_file: str, output_file: str, data: bytes) -> dict[str, object]:
    return {
        "encodedFile": encoded_file,
        "outputFile": output_file,
        "compression": "raw-deflate+base64",
        "byteCount": len(data),
        "sha256": digest(data),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    args = parser.parse_args()
    source = args.source_root.resolve()

    installer = read_regular(
        source / "firmware/yokoi-bootfriend/installer/yokoi_boot_installer.wsc",
        256 * 1024,
    )
    service = read_regular(
        source / "firmware/yokoi-cart-service/yokoi-cart-service.bfb",
        64 * 1024,
    )
    toolkit_path = source / "build/SwanSong-Yokoi-Toolkit.zip"
    toolkit = read_regular(toolkit_path, 4 * 1024 * 1024)
    if len(installer) < 16 or installer[-16] != 0xEA:
        raise SystemExit("Yokoi installer does not have a valid Color ROM footer")
    if not service.startswith(b"bF"):
        raise SystemExit("Yokoi Cart Service is not a BootFriend image")

    installer_name = "yokoi-boot-installer.zlib.b64"
    service_name = "yokoi-cart-service.zlib.b64"
    toolkit_name = "SwanSong-Yokoi-Toolkit.zip"
    (PAYLOAD / installer_name).write_bytes(encode(installer))
    (PAYLOAD / service_name).write_bytes(encode(service))
    shutil.copyfile(toolkit_path, PAYLOAD / toolkit_name)

    manifest = {
        "schema": "swan-song-yokoi-hardware-v2",
        "version": "0.3.0-development.1",
        "releaseReady": False,
        "source": {
            "kind": "bundled-toolkit",
            "file": toolkit_name,
            "byteCount": len(toolkit),
            "sha256": digest(toolkit),
        },
        "installer": artifact(installer_name, "Yokoi Boot Installer.wsc", installer),
        "cartService": artifact(service_name, "yokoi-cart-service.bfb", service),
    }
    (PAYLOAD / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "version": manifest["version"],
                "installerSHA256": manifest["installer"]["sha256"],
                "cartServiceSHA256": manifest["cartService"]["sha256"],
                "sourceSHA256": manifest["source"]["sha256"],
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
