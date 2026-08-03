# Data-producer provenance fixture

This clean-room WonderSwan Color ROM copies one distinctive six-byte table
from cartridge ROM into CPU-visible cartridge SRAM at `0x13456`, then halts.
It exists solely to regression-test SwanSong's bounded producer trace: all six
target bytes must have one exact CPU writer and exact executed cartridge
lineage, while the public result returns no SRAM values or private addresses.

The fixture contains no BIOS, firmware, or commercial game data. Build it with
the pinned Wonderful toolchain using `make clean all`.

- ROM SHA-256: `cadfbb6317efff57978f51c1d1230c62f2f9d9657eddb14a65e03c37d93e774c`
- Distinctive source offset: `0x1FF1F`
- Target CPU address: `0x13456` (six bytes)
