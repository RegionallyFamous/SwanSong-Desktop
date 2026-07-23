# SwanSong roadmap

This roadmap describes intended outcomes, not promises or compatibility claims.
Release notes and the issue tracker are authoritative for shipped behavior.

## 0.9 beta

- Validate Translation Shelf end to end with source-free release packages:
  exact-original selection, safe relative paths, in-memory IPS application,
  output and cartridge checksums, separate library identity, duplicate
  adoption, save/state isolation, and deterministic repair of a damaged
  managed copy.
- Prove Translation Shelf stays network-silent and never changes, copies into
  the package, or publishes the selected original game.
- Keep the SwanSong Fun Tester and all launch-confidence language behind
  **Show developer tools**, including at compact and wide window sizes.
- Exercise the signed 0.9 beta updater from 0.8.1. Stable-only clients must not
  see it; beta-enabled clients must preserve libraries, saves, settings, and
  projects through installation and relaunch.
- Run the complete Apple silicon, Intel, signing, notarization, Gatekeeper,
  privacy, source, SBOM, checksum, attestation, Wiki, and public-download gates.
- Record hands-on results in the 0.9 beta checklist instead of treating an
  automated pass as human approval.

## 1.0 readiness

- Expand revision-specific compatibility evidence without treating a boot or
  first frame as a full-game verdict.
- Complete hands-on player, controller, update, translation, homebrew, Studio,
  Story Forge, and supported hardware testing on Apple silicon and Intel.
- Publish a concise known-limits and compatibility report with revision,
  hardware, and evidence scope kept explicit.
- Retain and verify manual native update checks, opt-in automatic checks and
  downloads, stable/beta selection, signed-feed rejection paths, and update
  installation from immutable GitHub Release assets.
- Review GPL corresponding-source completeness with a license specialist.
- Decide whether 1.0 needs a drag-to-Applications disk image or whether the
  notarized universal ZIP remains the clearest supported install path.

## Later

- Expand accessibility documentation and community compatibility testing.
- Localize onboarding and the highest-traffic help pages.
- Expand the rights-safe press kit with new screenshots only when the running
  release and fixture provenance are recorded beside each image.
