# Mapper-window owner matrix fixture

This clean-room WonderSwan Color ROM is the ABI-9 control for executed mapper
context. Four isolated Screen 1 pixels are copied by fixed V30MZ instructions
from cartridge windows 2, 3, 4, and F. After those reads, the routine switches
to inactive mapper banks containing byte-identical decoys and records only the
final mapper values in internal RAM.

The layout deliberately fixes the source payloads and MOVSB callers. The live
smoke gate can therefore require exact reader/caller context, mapper window and
bank, resolved cartridge operand, final raster writer, and zero outside
consumers. Transparent neighboring pixels are negative controls with no raster
lineage. A content scan cannot distinguish an active payload from its decoy.

Build the checked-in 2 MiB ROM with the pinned Wonderful toolchain:

```sh
make all
```

The fixture sources are CC0-1.0. The linked Wonderful target-wswan runtime
keeps its zlib-style notice in `LICENSE.target-wswan-syslibs`.

