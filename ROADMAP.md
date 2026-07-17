# SwanSong roadmap

This roadmap describes intended outcomes, not promises or compatibility claims.
Release notes and the issue tracker are authoritative for shipped behavior.

## 0.3 beta closure

- Publish guarded route recording, Original/Patched paired verification, and
  deterministic homebrew playtesting as an explicitly marked GitHub
  prerelease built from its exact signed source tag.
- Prove the 0.2-to-0.3 Sparkle update on beta-enabled clients while stable-only
  clients remain on their selected channel and all private library and project
  data survives the transition.
- Keep local MCP off by default, token-authenticated, session-local, and limited
  to its documented tool and data allowlists. Exercise enable, control, revoke,
  and denied-request paths on a clean supported Mac.
- Developer ID sign, notarize, staple, Gatekeeper-assess, and inspect the
  universal Apple silicon and Intel archive, including the corrected Finder,
  Dock, and direct-launch icon behavior.
- Publish the exact corresponding-source archive, SHA-256 checksums,
  machine-readable manifest, human release notes, beta testing guide, and
  matching repo-backed Wiki revision.
- Keep the Homebrew Catalog visibly **Coming Soon** and network-silent until the
  first explicitly licensed Story Forge ROM, immutable release asset, signed
  non-empty catalog, and production public key all pass the release gate.
- Keep SwanSong Desktop and the separate Analogue Pocket `swansong-core`
  release lanes explicit. Desktop's manual SD-card tool may install only an
  immutable, authorized stable Core release after its manifest and checksum
  agree; it must not build, publish, or silently update the FPGA product.
- Retain Open IPL, controller, save/state, portrait, accessibility,
  minimum-macOS, A/V soak, and physical input acceptance from 0.2 without
  treating a successful boot or automation command as a compatibility verdict.

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
