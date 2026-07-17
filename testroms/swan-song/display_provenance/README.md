# Display provenance fixtures

These two clean-room WonderSwan Color ROMs provide known final-display owners
from engine ABI 6 plus exact upstream cartridge sources and outside consumers
for ABI 7. They contain no commercial game material.

- `display_provenance_horizontal.wsc` is horizontal and uses planar 4bpp tile
  raster data.
- `display_provenance_vertical.wsc` is vertical and uses packed 4bpp tile
  raster data.

Both fixtures draw a solid Screen 1 background, one isolated Screen 2 tile,
and one priority sprite. Each uses a different palette entry and CPU-written
map, raster, palette, and OAM data. The engine smoke test probes stable pixels
from all three final layers and requires exact cell, tile, raster width,
palette source, and non-unknown final-writer results. The vertical assertions
also exercise canonical native rotation. Tile 1 is copied from a distinctive
ROM-resident 32-byte table, XOR-decoded through the CPU, and reused across
Screen 1, allowing the ABI 7 smoke test to locate its linked offset, require an
exact transformed raster trace, and
require at least one outside-rectangle consumer of the same source bytes.

The fixture source is CC0-1.0. The linked Wonderful target-wswan runtime keeps
its zlib-style notice in `LICENSE.target-wswan-syslibs`.

Build both ROMs with the pinned Wonderful toolchain:

```sh
make clean all
```

The checked-in ROM hashes and expected source addresses are recorded in
`Scripts/check-live-engine.sh` so rebuild drift fails closed.
