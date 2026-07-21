# Static-analysis seed-v2 retained-prefetch fixture

This CC0 WonderSwan Color ROM is the smallest public ABI-10 known-answer
fixture for separating an executed instruction's fetch origin from its data
operand's mapper context.

The fixed setup code selects mapper bank `E2` for CPU window 2 and far-jumps to
`2000:8000`, starting with an empty prior prefetch context. The bank-E2 routine
executes `OUT 0xC2,AL` to select bank `E6`. Its next terminal opcode is a
prefetched bank-E2 `REP MOVSW`: the prefix begins at `2000:8004` and the
terminal opcode is at `2000:8005`. Bank E6 deliberately contains `HLT` at the
prefix address. The retained two-element copy reads the complete aligned
four-byte raster owner from `E6:9000` and writes it to `0000:4020`.

The exact visible result is one red Screen 1 pixel at native `(0,0)` with the
neighbor at `(1,0)` remaining black. `expected.json` records the exact public
source-read and instruction-fetch facts. In particular, the raster source is
the four-byte span at ROM offset `0x69000` under mapper bank `E6`, while each
sealed execution consumes the two-byte logical instruction at ROM offset
`0x28004` under mapper bank `E2`. A content lookup cannot substitute one for
the other: the old source span is a decoy, and the new bank halts at the
retained prefix address.

The public expected record retains the full observed 16-bit mapper registers
(`FFE6` for the source read and `FFE2` for the consumed instruction byte) while
recording the aperture-masked cartridge operands separately. The preserved
reset-state high byte is not normalized away merely because it maps to the
same 2 MiB ROM offset.

The reproducible ROM SHA-256 is
`f7a57414097e951fe927ec7e78f79b3ef3530baad8ca9ac0242911d91deaac94`.
The bounded SwanSong integration run produced the public video digest
`424bab4a90dd7a7c`, one exact selected trace, two sealed execution contexts,
and four consumed fetch-byte rows. `receipt.json` binds that source-free result
to the exact fixture inputs, Wonderful tools, and ABI-10 engine build used for
this control. The approved full live suite reproduced the exact result twice
and passed the engine, prefetch, provenance, mapper, and Swift boundary gates.

The falsifier is a missing or out-of-rectangle red pixel, conservative ABI-9
lineage for any byte in the aligned owner, or any fetch context that does not
seal to the bank-E2 prefix/opcode pair while the complete source read resolves
independently to bank E6. Do not widen this control into operand, register, or
runtime-v5 export work.

Build the checked-in 2 MiB ROM with the pinned Wonderful toolchain:

```sh
make clean all WONDERFUL_TOOLCHAIN=/opt/wonderful
```

All fixture-authored sources and metadata are CC0-1.0. The linked Wonderful
target-wswan runtime keeps its zlib-style notice in
`LICENSE.target-wswan-syslibs`.
