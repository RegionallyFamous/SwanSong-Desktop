# SwanSong roadmap

This roadmap describes intended outcomes, not promises or compatibility claims.
Release notes and the issue tracker are authoritative for shipped behavior.

## 0.2 beta closure

- Publish the Open-IPL-only 0.2 build as an explicitly marked GitHub
  prerelease, built from its exact signed source tag on a clean signing Mac.
- Developer ID sign, notarize, staple, and pass Gatekeeper assessment for the
  universal Apple silicon and Intel archive.
- Publish the exact corresponding-source archive, SHA-256 checksums,
  machine-readable manifest, human release notes, and beta testing guide.
- Complete install, Open IPL, keyboard, standard GameController, save/state,
  portrait, accessibility, and minimum-macOS acceptance passes. Treat devices
  that macOS does not expose through GameController as unsupported, not as
  silently guessed raw HID layouts.
- Keep the Homebrew Catalog visibly **Coming Soon** and network-silent until the
  first explicitly licensed Story Forge ROM, immutable release asset, signed
  non-empty catalog, and production public key all pass the release gate.
- Keep SwanSong Desktop and the separate Analogue Pocket `swansong-core`
  release lanes explicit; neither product installs or updates the other.
- Ship the native Sparkle 2 updater against the signed GitHub-hosted appcast,
  with manual checks always available, automatic checks/downloads opt-in,
  system profiling disabled, and stable/beta channel behavior covered by the
  release gate.

## 1.0 readiness

- Expand revision-specific compatibility evidence without treating a boot or
  first frame as a full-game verdict.
- Complete release testing on supported Apple silicon and Intel hardware.
- Publish a concise known-limits and compatibility report.
- Retain and verify manual native update checks, opt-in automatic checks and
  downloads, stable/beta selection, signed-feed rejection paths, and update
  installation from immutable GitHub Release assets.
- Review GPL corresponding-source completeness with a license specialist.

## Later

- Consider a polished drag-to-Applications disk image.
- Expand accessibility documentation and community compatibility testing.
- Add a launch website, rights-safe press kit, and localized onboarding.
- Consider software bills of materials and reproducible-build attestations.
