# Input-frame bridge fixture

This clean-room WonderSwan Color ROM samples the keypad once per VBlank and
records each state transition in a fixed internal-RAM trace. The live ares
smoke gate drives an adjacent A/X1/A change followed by three explicit A
release/press cycles, then requires every transition at the fixture boundary
in that exact order.

The fixture catches frontends that update only their desired input state but
leave ares' cached input nodes stale until a later core poll. Its source is
CC0-1.0. The linked Wonderful target-wswan runtime keeps its zlib-style notice
in `LICENSE.target-wswan-syslibs`.

Build the checked-in ROM with the pinned Wonderful toolchain:

```sh
make clean all
```
