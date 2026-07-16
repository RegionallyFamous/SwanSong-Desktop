#!/usr/bin/env python3
"""Adversarial self-test for the corresponding-source archive validator."""

from __future__ import annotations

import io
import lzma
import os
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


VERSION = "9.8.7"
ROOT = f"SwanSong-{VERSION}-source"
ARCHIVE_NAME = f"SwanSong-{VERSION}-source.tar.xz"
SOURCE_COMMIT = "1" * 40
ARES_COMMIT = "2" * 40
REQUIRED_FILES = (
    "SOURCE_ARCHIVE_PROVENANCE.json",
    "Package.swift",
    "Engine/ares-headless.patch",
    "Dependencies/ares.lock.json",
    "Sources/CSwanEngine/include/swan_engine.h",
    "Dependencies/ares-source/LICENSE",
    "Dependencies/ares-source/ares/ws/ws.cpp",
    "Dependencies/ares-source/ares/ws/system/system.cpp",
)


class ZeroStream:
    def __init__(self, byte_count: int) -> None:
        self.remaining = byte_count

    def read(self, size: int = -1) -> bytes:
        if self.remaining == 0:
            return b""
        if size < 0 or size > self.remaining:
            size = self.remaining
        self.remaining -= size
        return b"\0" * size


def directory(name: str) -> tarfile.TarInfo:
    member = tarfile.TarInfo(name)
    member.type = tarfile.DIRTYPE
    member.mode = 0o755
    return member


def regular(name: str, payload: bytes = b"source\n") -> tuple[tarfile.TarInfo, io.BytesIO]:
    member = tarfile.TarInfo(name)
    member.type = tarfile.REGTYPE
    member.mode = 0o644
    member.size = len(payload)
    return member, io.BytesIO(payload)


def zero_regular(name: str, byte_count: int) -> tuple[tarfile.TarInfo, ZeroStream]:
    member = tarfile.TarInfo(name)
    member.type = tarfile.REGTYPE
    member.mode = 0o644
    member.size = byte_count
    return member, ZeroStream(byte_count)


def valid_members() -> list[tuple[tarfile.TarInfo, io.BytesIO | None]]:
    members: list[tuple[tarfile.TarInfo, io.BytesIO | None]] = [
        (directory(ROOT), None)
    ]
    for relative_path in REQUIRED_FILES:
        if relative_path == "SOURCE_ARCHIVE_PROVENANCE.json":
            payload = (
                '{"schema":"swan-song-source-v1",'
                f'"sourceCommit":"{SOURCE_COMMIT}",'
                f'"aresCommit":"{ARES_COMMIT}"}}\n'
            ).encode()
        elif relative_path == "Dependencies/ares.lock.json":
            payload = f'{{"commit":"{ARES_COMMIT}"}}\n'.encode()
        else:
            payload = b"source\n"
        members.append(regular(f"{ROOT}/{relative_path}", payload))
    return members


def replace_regular(
    members: list[tuple[tarfile.TarInfo, io.BytesIO | None]],
    relative_path: str,
    payload: bytes,
) -> list[tuple[tarfile.TarInfo, io.BytesIO | None]]:
    full_path = f"{ROOT}/{relative_path}"
    return [entry for entry in members if entry[0].name != full_path] + [
        regular(full_path, payload)
    ]


def write_archive(
    path: Path, members: list[tuple[tarfile.TarInfo, io.BytesIO | None]]
) -> None:
    with tarfile.open(path, "w:xz") as output:
        for member, payload in members:
            output.addfile(member, payload)


def run_validator(validator: Path, archive: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(validator),
            "--source-commit",
            SOURCE_COMMIT,
            "--ares-commit",
            ARES_COMMIT,
            str(archive),
        ],
        check=False,
        capture_output=True,
        text=True,
    )


def expect_pass(validator: Path, archive: Path, label: str) -> None:
    result = run_validator(validator, archive)
    if result.returncode != 0:
        raise AssertionError(f"validator rejected {label}: {result.stderr.strip()}")


def expect_failure(validator: Path, archive: Path, label: str) -> None:
    result = run_validator(validator, archive)
    if result.returncode == 0:
        raise AssertionError(f"validator unexpectedly accepted {label}")


def main() -> int:
    validator = Path(__file__).with_name("validate-source-archive.py")
    with tempfile.TemporaryDirectory(prefix="swan-source-validator-selftest.") as root:
        temp_root = Path(root)
        archive = temp_root / ARCHIVE_NAME

        write_archive(archive, valid_members())
        expect_pass(validator, archive, "a valid source archive")

        cases: list[
            tuple[str, list[tuple[tarfile.TarInfo, io.BytesIO | None]]]
        ] = []
        cases.append(
            (
                "firmware outside the ares subtree",
                valid_members() + [regular(f"{ROOT}/Firmware/BOOT.ROM")],
            )
        )
        cases.append(
            (
                "a generic firmware-like binary",
                valid_members() + [regular(f"{ROOT}/boot.bin")],
            )
        )
        cases.append(
            (
                "Git metadata",
                valid_members() + [regular(f"{ROOT}/.git/config")],
            )
        )
        cases.append(("a traversal path", valid_members() + [regular("../escape")]))
        cases.append(("an absolute path", valid_members() + [regular("/escape")]))
        cases.append(
            ("a backslash path", valid_members() + [regular(f"{ROOT}\\escape")])
        )
        cases.append(
            ("a second root", valid_members() + [regular("OtherRoot/escape")])
        )
        cases.append(
            (
                "a duplicate path",
                valid_members() + [regular(f"{ROOT}/Package.swift")],
            )
        )
        cases.append(("missing required source", valid_members()[:-1]))
        cases.append(
            (
                "mismatched source provenance",
                replace_regular(
                    valid_members(),
                    "SOURCE_ARCHIVE_PROVENANCE.json",
                    (
                        '{"schema":"swan-song-source-v1",'
                        f'"sourceCommit":"{"3" * 40}",'
                        f'"aresCommit":"{ARES_COMMIT}"}}\n'
                    ).encode(),
                ),
            )
        )
        cases.append(
            (
                "a mismatched archived ares lock",
                replace_regular(
                    valid_members(),
                    "Dependencies/ares.lock.json",
                    f'{{"commit":"{"3" * 40}"}}\n'.encode(),
                ),
            )
        )

        symlink = tarfile.TarInfo(f"{ROOT}/link")
        symlink.type = tarfile.SYMTYPE
        symlink.linkname = "Package.swift"
        cases.append(("a symbolic link", valid_members() + [(symlink, None)]))
        hardlink = tarfile.TarInfo(f"{ROOT}/hardlink")
        hardlink.type = tarfile.LNKTYPE
        hardlink.linkname = f"{ROOT}/Package.swift"
        cases.append(("a hard link", valid_members() + [(hardlink, None)]))
        device = tarfile.TarInfo(f"{ROOT}/device")
        device.type = tarfile.CHRTYPE
        cases.append(("a device node", valid_members() + [(device, None)]))

        for label, members in cases:
            write_archive(archive, members)
            expect_failure(validator, archive, label)

        write_archive(
            archive,
            valid_members()
            + [zero_regular(f"{ROOT}/oversized", 64 * 1024 * 1024 + 1)],
        )
        expect_failure(validator, archive, "an oversized source entry")

        write_archive(
            archive,
            valid_members()
            + [
                zero_regular(f"{ROOT}/total/{index}", 60 * 1024 * 1024)
                for index in range(5)
            ],
        )
        expect_failure(validator, archive, "an oversized expanded source archive")

        many_members = valid_members()
        for index in range(20_001):
            many_members.append(regular(f"{ROOT}/many/{index}", b""))
        write_archive(archive, many_members)
        expect_failure(validator, archive, "too many source entries")

        write_archive(archive, valid_members())
        archive_bytes = archive.read_bytes()
        archive.write_bytes(archive_bytes[: len(archive_bytes) // 2])
        expect_failure(validator, archive, "a truncated XZ source archive")

        archive.write_bytes(b"not xz")
        expect_failure(validator, archive, "a non-XZ payload")

        with archive.open("wb") as output:
            output.write(lzma.compress(b"invalid tar"))
            output.truncate(64 * 1024 * 1024 + 1)
        expect_failure(validator, archive, "an oversized compressed source archive")

        renamed = temp_root / "Renamed-source.tar.xz"
        os.replace(archive, renamed)
        expect_failure(validator, renamed, "a wrongly named source archive")

    print(
        "PASS source archive validator rejects firmware-like payloads, Git "
        "metadata, unsafe roots and paths, links and devices, duplicates, "
        "missing or mismatched source provenance, wrong compression, and "
        "resource exhaustion"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
