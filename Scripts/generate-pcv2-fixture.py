#!/usr/bin/env python3
"""Generate SwanSong's clean-room Pocket Challenge V2 integration fixture.

The output is a build-only 128 KiB ``.pc2`` cartridge authored entirely as
80186 machine bytes. It contains no commercial program, dumped firmware,
font, SDK object, or external artwork. The program draws a moving monochrome
checkerboard, emits a deterministic Channel 1 tone, records all three Pocket
Challenge V2 keypad rows in IRAM, and leaves an exact KARNAK ADPCM result for
the live probe to inspect.
"""

from __future__ import annotations

import argparse
from pathlib import Path


ROM_SIZE = 128 * 1024
PROGRAM_OFFSET = 0x10  # Physical 40010h through the PCV2 pinstrap path.
LEGACY_RESET_TRAP_OFFSET = 0x10000
MARKER_OFFSET = 0x10400
FLASH_ROUNDTRIP_OFFSET = 0x10480
FOOTER_OFFSET = ROM_SIZE - 16
ROM_NAME = "swan_song_pcv2_integration.pc2"
MARKER = b"SWAN-SONG-PCV2-CLEAN-ROOM-INTEGRATION-V1\0"

KEYPAD_ROW_CLEAR_CIRCLE_PASS = 0x3FF0
KEYPAD_ROW_VIEW_ESCAPE_RIGHT = 0x3FF1
KEYPAD_ROW_LEFT_DOWN_UP = 0x3FF2
KARNAK_RESULT = 0x3FFE
SCROLL_COUNTER = 0x3FFF
PINSTRAP_LCD_STATE = 0x3FF8
PINSTRAP_ENTRY_SEGMENT = 0x3FFA
PINSTRAP_ACCUMULATOR = 0x3FF4
PINSTRAP_FLAGS = 0x3FF6


class Program:
    """Small rel8-aware 80186 byte builder used only by this fixture."""

    def __init__(self) -> None:
        self.data = bytearray()
        self.labels: dict[str, int] = {}
        self.fixups: list[tuple[int, str]] = []

    def emit(self, *values: int) -> None:
        self.data.extend(values)

    def label(self, name: str) -> None:
        if name in self.labels:
            raise ValueError(f"duplicate program label: {name}")
        self.labels[name] = len(self.data)

    def branch8(self, opcode: int, target: str) -> None:
        self.emit(opcode, 0)
        self.fixups.append((len(self.data) - 1, target))

    def resolve(self) -> bytes:
        for displacement_at, target in self.fixups:
            if target not in self.labels:
                raise ValueError(f"unknown program label: {target}")
            displacement = self.labels[target] - (displacement_at + 1)
            if not -128 <= displacement <= 127:
                raise ValueError(f"rel8 branch to {target} is out of range")
            self.data[displacement_at] = displacement & 0xFF
        return bytes(self.data)


def _word(value: int) -> tuple[int, int]:
    return value & 0xFF, (value >> 8) & 0xFF


def _out8(code: Program, port: int, value: int) -> None:
    code.emit(0xB0, value, 0xE6, port)  # mov al,imm8; out imm8,al


def _store_al(code: Program, address: int) -> None:
    code.emit(0xA2, *_word(address))  # mov [disp16],al


def _scan_keypad_row(code: Program, selector: int, address: int) -> None:
    _out8(code, 0xB5, selector)
    code.emit(0x90, 0x90, 0x90, 0x90)  # documented matrix settling interval
    code.emit(0xE4, 0xB5, 0x24, 0x0F)  # in al,b5h; and al,0fh
    _store_al(code, address)


def program() -> bytes:
    code = Program()

    # Capture evidence before touching normal WonderSwan machine state. A
    # PCV2 pinstrap boot enters at 4000:0010 with reset AX/flags and the LCD
    # still disabled.
    code.emit(0xA3, *_word(PINSTRAP_ACCUMULATOR))  # mov [disp16],ax
    code.emit(0xBC, 0xEC, 0x3F)  # mov sp,3fech (MOV preserves flags)
    code.emit(0x9C, 0x58)  # pushf; pop ax
    code.emit(0xA3, *_word(PINSTRAP_FLAGS))  # mov [disp16],ax
    code.emit(0xE4, 0x14)  # in al,LCD_CTRL
    _store_al(code, PINSTRAP_LCD_STATE)
    code.emit(0x8C, 0xC8)  # mov ax,cs
    code.emit(0xA3, *_word(PINSTRAP_ENTRY_SEGMENT))  # mov [disp16],ax

    # Flat IRAM segments, interrupts disabled, display hidden during setup.
    code.emit(0xFA, 0xFC)  # cli; cld
    code.emit(0x31, 0xC0)  # xor ax,ax
    code.emit(0x8E, 0xD8, 0x8E, 0xC0)  # mov ds,ax; mov es,ax
    _out8(code, 0x14, 0x00)  # LCD off
    _out8(code, 0x00, 0x00)  # all display layers off
    _out8(code, 0x07, 0x00)  # Screen 1 map at IRAM 0000h
    _out8(code, 0x01, 0x00)  # palette 0/color 0 backdrop

    # A deterministic eight-shade lookup and a four-shade screen palette.
    for port, value in ((0x1C, 0x10), (0x1D, 0x32), (0x1E, 0x54), (0x1F, 0x76)):
        _out8(code, port, value)
    code.emit(0xB8, 0x10, 0x32)  # mov ax,3210h
    code.emit(0xBA, 0x20, 0x00)  # mov dx,0020h
    code.emit(0xEF)  # out dx,ax

    # Fill Screen 1 with alternating tile 0/tile 1 entries.
    code.emit(0x31, 0xFF)  # xor di,di
    code.emit(0xB9, 0x00, 0x04)  # mov cx,1024
    code.emit(0x31, 0xC0)  # xor ax,ax
    code.label("fill_map")
    code.emit(0xAB)  # stosw
    code.emit(0x35, 0x01, 0x00)  # xor ax,1
    code.branch8(0xE2, "fill_map")  # loop fill_map

    # Tile 1 is an authored 2bpp stripe. Tile 0 remains reset-transparent.
    code.emit(0xBF, 0x10, 0x20)  # mov di,2010h
    code.emit(0xB8, 0xAA, 0x55)  # mov ax,55aah
    code.emit(0xB9, 0x08, 0x00)  # mov cx,8
    code.emit(0xF3, 0xAB)  # rep stosw

    # Channel 1 uses a synthetic alternating 4-bit waveform in IRAM 3000h.
    code.emit(0xBF, 0x00, 0x30)  # mov di,3000h
    code.emit(0xB8, 0xF0, 0xF0)  # mov ax,f0f0h
    code.emit(0xB9, 0x08, 0x00)  # mov cx,8
    code.emit(0xF3, 0xAB)  # rep stosw
    _out8(code, 0x8F, 0xC0)  # wave base 3000h
    code.emit(0xB8, 0x26, 0x07)  # approximately 440 Hz
    code.emit(0xBA, 0x80, 0x00)
    code.emit(0xEF)  # out dx,ax (Channel 1 frequency)
    _out8(code, 0x88, 0xFF)  # full stereo volume
    _out8(code, 0x90, 0x01)  # enable Channel 1
    _out8(code, 0x91, 0x01)  # speaker enabled

    # Exercise PCV2's KARNAK ADPCM ports. Four 7 nibbles advance the clean
    # reset accumulator from 100h to 17eh, so D9h must return BFh.
    code.emit(0xBA, 0xD6, 0x00, 0xB0, 0x80, 0xEE)
    code.emit(0xBA, 0xD8, 0x00, 0xB0, 0x77)
    code.emit(0xEE, 0xEE, 0xEE, 0xEE)
    code.emit(0xBA, 0xD9, 0x00, 0xEC)
    _store_al(code, KARNAK_RESULT)

    _out8(code, 0x00, 0x01)  # Screen 1 enabled
    _out8(code, 0x14, 0x01)  # LCD on

    code.label("main")
    _scan_keypad_row(code, 0x10, KEYPAD_ROW_CLEAR_CIRCLE_PASS)
    _scan_keypad_row(code, 0x20, KEYPAD_ROW_VIEW_ESCAPE_RIGHT)
    _scan_keypad_row(code, 0x40, KEYPAD_ROW_LEFT_DOWN_UP)

    # Advance horizontal scroll exactly once per vblank. The checkerboard is
    # therefore both visibly non-uniform and frame-to-frame deterministic.
    code.label("wait_active")
    code.emit(0xE4, 0x02, 0x3C, 0x90)  # in al,02h; cmp al,144
    code.branch8(0x73, "wait_active")  # jae wait_active
    code.label("wait_vblank")
    code.emit(0xE4, 0x02, 0x3C, 0x90)
    code.branch8(0x72, "wait_vblank")  # jb wait_vblank
    code.emit(0xFE, 0x06, *_word(SCROLL_COUNTER))  # inc byte [counter]
    code.emit(0xA0, *_word(SCROLL_COUNTER))  # mov al,[counter]
    code.emit(0xE6, 0x10)  # out 10h,al
    code.branch8(0xEB, "main")

    return code.resolve()


def footer() -> bytes:
    result = bytearray(16)
    result[0:5] = b"\xEA\x00\x00\x00\xF0"  # jmp far F000:0000
    result[5] = 0x00  # maintenance byte
    result[6] = 0x00  # homebrew/test developer ID
    result[7] = 0x00  # ASWAN-compatible monochrome footer
    result[8] = 0x52  # repository-authored diagnostic ID
    result[9] = 0x01  # fixture format version
    result[10] = 0x00  # 1 Mbit / 128 KiB ROM
    result[11] = 0x00  # PCV2 persistence is the program flash itself
    result[12] = 0x04  # 16-bit ROM bus, horizontal orientation
    result[13] = 0x00  # exact KARNAK selection comes from the PCV2 route
    return bytes(result)


def image() -> bytes:
    machine_code = program()
    result = bytearray(b"\xFF" * ROM_SIZE)
    if PROGRAM_OFFSET + len(machine_code) > LEGACY_RESET_TRAP_OFFSET:
        raise ValueError("PCV2 pinstrap program overlaps its reset-path trap")
    if LEGACY_RESET_TRAP_OFFSET + 4 > MARKER_OFFSET:
        raise ValueError("PCV2 reset-path trap overlaps its identity marker")
    if MARKER_OFFSET + len(MARKER) > FLASH_ROUNDTRIP_OFFSET:
        raise ValueError("PCV2 identity marker overlaps the flash sentinel")
    if not FLASH_ROUNDTRIP_OFFSET < FOOTER_OFFSET:
        raise ValueError("PCV2 flash sentinel overlaps the footer")
    result[PROGRAM_OFFSET : PROGRAM_OFFSET + len(machine_code)] = machine_code
    # A standard WonderSwan footer-vector boot stops here. Public integration
    # tests therefore prove the PCV2 direct 4000:0010 route by reaching video.
    result[LEGACY_RESET_TRAP_OFFSET : LEGACY_RESET_TRAP_OFFSET + 4] = (
        b"\xFA\xF4\xEB\xFD"
    )
    result[MARKER_OFFSET : MARKER_OFFSET + len(MARKER)] = MARKER
    result[FLASH_ROUNDTRIP_OFFSET] = 0xA5
    result[FOOTER_OFFSET:] = footer()
    result[-2:] = (sum(result[:-2]) & 0xFFFF).to_bytes(2, "little")
    return bytes(result)


def generate(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(image())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, nargs="?", default=Path(ROM_NAME))
    args = parser.parse_args()
    try:
        generate(args.output)
    except (OSError, ValueError) as error:
        raise SystemExit(f"cannot generate PCV2 fixture: {error}") from error
    print(f"generated {args.output} ({args.output.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
