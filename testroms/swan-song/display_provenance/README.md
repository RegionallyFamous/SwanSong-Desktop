# Display provenance fixtures

These clean-room WonderSwan ROMs provide known final-display owners from engine
ABI 6 plus the current ABI 9 exact upstream cartridge sources, outside
consumers, private sprite/OAM ownership, runtime-generated monochrome palette
classification, and conservative source-origin classification. They contain no
commercial game material.

- `display_provenance_horizontal.wsc` is horizontal and uses planar 4bpp tile
  raster data.
- `display_provenance_vertical.wsc` is vertical and uses packed 4bpp tile
  raster data.
- `source_lineage_blocked.wsc` deliberately moves one ROM raster byte through
  an opaque stack round trip. The ABI-9 source probe must classify the selected
  raster lineage as conservative and nonexact, stop with the pinned blocked
  report, publish no private details, and authorize no prototype.
- `mono_palette_out_owner.ws` is horizontal monochrome and writes its shade
  controls and two-byte palette through literal V30MZ `OUT`/`OUTW`
  instructions. Its selected palette component is the one-byte selector at
  port `0x21`; this fixture does not claim ownership of the separate shade-LUT
  dependency.

Both fixtures draw a solid Screen 1 background, one isolated Screen 2 tile,
and one priority sprite. Each uses a different palette entry and CPU-written
map, raster, palette, and OAM data. The engine smoke test probes stable pixels
from all three final layers and requires exact cell, tile, raster width,
palette source, and non-unknown final-writer results. The vertical assertions
also exercise canonical native rotation. Tile 1 is copied from a distinctive
ROM-resident 32-byte table, XOR-decoded through the CPU, and reused across
Screen 1, allowing the source-provenance smoke test to locate its linked offset,
require an exact transformed raster trace, and
require at least one outside-rectangle consumer of the same source bytes.
The current ABI 9 smoke lane also requires the sprite's complete OAM range and
writer privately, validates `spriteAttribute` selection, and accepts a
conservative trace only when its private reason and V30 origin are internally
consistent. Public automation receives only source-free counts and hashes.

The monochrome fixture exposes a color-2 Screen 1 pixel at native coordinate
`0,0` and a palette-4/color-0 transparency control at `9,0`. Its map and 2bpp
planar raster are CPU-written in IRAM. The smoke lane requires the selected map,
raster, and one-byte palette selector to have known final writers and exact
runtime-generated ABI-9 lineage without cartridge, conservative, unknown, or
overflow claims.

The fixture sources are CC0-1.0. The linked Wonderful target-wswan runtime keeps
its zlib-style notice in `LICENSE.target-wswan-syslibs`.

Build all ROMs with the pinned Wonderful toolchain:

```sh
make clean all
```

The checked-in ROM hashes and expected source addresses are recorded in
`Scripts/check-live-engine.sh` so rebuild drift fails closed.
