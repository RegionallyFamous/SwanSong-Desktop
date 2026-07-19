# SwanSong roadmap

This roadmap describes intended outcomes, not promises or compatibility claims.
Release notes and the issue tracker are authoritative for shipped behavior.

## 0.5 release closure

- Validate Story Forge project creation, every schema-v3 stage and report,
  ImageGen-only art evidence, catalog originality/status, migration, lockfile,
  EPUB/PDF proof, privacy, and the revision-to-Studio handoff against both
  passing and deliberately incomplete novels.
- Validate Cartridge Lab against a controlled WonderSwan Color/SwanCrystal
  hardware matrix: serial discovery, Yokoi Boot service loading, cartridge
  inspection, interrupted ROM/save backups, exact-size save restore, physical
  A+B write confirmation, readback, and recovery-conscious installer media.

- Validate SwanSong Studio's New, Assets, Build, Test, Play, Profile, Evidence,
  and Release workspaces against SwanSong SDK 0.4.0-or-newer projects.
- Exercise Doctor, Dev, Scenario Recorder, Evidence Diff, deterministic input
  fuzzing, Sprite/VRAM profiling, Asset Optimizer, and Save/RTC Laboratory with
  both successful projects and bounded failure cases.
- Exercise the six visual-authoring documents, read-only replay timelines, and
  deterministic failing-plan minimization with valid and rejected contracts.
- Prove that Release accepts only inspected, current, hash-bound PNG and WAV
  observations and rejects execution-only, incomplete, or stale evidence.
- Keep ownership explicit: the SDK owns Wonderful builds, assets, manifests,
  budgets, and release policy; SwanSong remains the only gameplay backend.
- Validate ABI 9 component-selective upstream source provenance, private
  sprite/OAM ownership and conservative-origin identity, private executed-read
  context, the complete installed MCP surface, and the SwanSong menu-bar status
  item. MCP must continue to expose only source-free counts and hashes.
- Prove the 0.4-to-0.5 Sparkle update on beta-enabled clients while stable-only
  clients remain on their selected channel and private library/project data is
  preserved.
- Keep local MCP off by default, token-authenticated, session-local, and limited
  to its documented tool and data allowlists.
- Developer ID sign, notarize, staple, Gatekeeper-assess, and inspect the
  universal Apple silicon and Intel archive from its exact release tag.
- Publish corresponding source, checksums, manifest, release notes, beta guide,
  and the matching repo-backed Wiki revision.
- Keep the published Homebrew Catalog network-silent until an explicit Browse,
  Refresh, or Add action, and keep the separate SwanSong Core release lane
  locked until its independent gates pass.
- Retain Open IPL, controller, save/state, portrait, accessibility,
  minimum-macOS, A/V soak, Translation Lab, and local-MCP regression coverage.
- Keep SwanSong Studio's external Python and Wonderful requirements visible
  until those dependencies can be bundled and independently verified in the
  signed application payload.
- Keep Story Forge and Cartridge Lab inside their documented privacy, hardware,
  payload, update, and release boundaries as 0.5 testing expands.

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
