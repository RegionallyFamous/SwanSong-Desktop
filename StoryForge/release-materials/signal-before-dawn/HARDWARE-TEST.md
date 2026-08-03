# Physical WonderSwan Color Test

**Status: PENDING**

No person has recorded a test of this release on a physical WonderSwan Color.
Emulator boot, checksum, audio, and screenshot evidence must not be reported as
a hardware pass. The structured companion record is
`docs/hardware-test-report.json`.

## Test Record

- Tester: not recorded
- Test date: not recorded
- Console model and identifier: not recorded
- Cartridge or flashcart and firmware: not recorded
- Pending test target ROM SHA-256:
  `e4f99c8abbe9f58fcd5a95b2b6e2f7ee5053e897a5564286b8eb5d7186997716`

## Checklist

- [ ] Record the WonderSwan Color model and the cartridge or flashcart used.
- [ ] Cold boot the exact packaged ROM and reach the title screen without a
  crash, corrupt tiles, or an unexpected reset.
- [ ] Verify A, B, START, X1, X2, X3, and X4 behavior against the controls in
  `docs/README.md`.
- [ ] Create a save, power the console off, power it on again, and load the
  save from cartridge SRAM.
- [ ] Inspect LCD contrast, color readability, flicker, tearing, and ghosting
  in the title, dark deck, radio, hatch, beacon, and sunrise scenes.
- [ ] Reach and identify all five endings: signal, together, hatch, reply, and
  sunrise.
- [ ] Listen through dialogue blips, scene effects, and music on the console
  speaker; note clipping, masking, harshness, or poor balance.
- [ ] Measure the actual cartridge label recess and confirm trim and bleed for
  the intended print process before treating `cartridge-label-v1.png` as
  print-ready. The current file is an art master, not an asserted physical
  template.

Keep the status **PENDING** until a person completes the checklist on physical
hardware, confirms the bound ROM hash, and records the device,
cartridge/flashcart, observations, and result. A future status change must
describe the actual test; it must not infer one from emulator evidence.
