# SwanSong roadmap

This roadmap describes intended outcomes, not promises or compatibility claims.
Release notes and the issue tracker are authoritative for shipped behavior.

## 0.4 beta closure

- Validate SwanSong Studio's New, Assets, Build, Test, Play, Profile, Evidence,
  and Release workspaces against SwanSong SDK 0.2.0-or-newer projects.
- Exercise Doctor, Dev, Scenario Recorder, Evidence Diff, deterministic input
  fuzzing, Sprite/VRAM profiling, Asset Optimizer, and Save/RTC Laboratory with
  both successful projects and bounded failure cases.
- Prove that Release accepts only inspected, current, hash-bound PNG and WAV
  observations and rejects execution-only, incomplete, or stale evidence.
- Keep ownership explicit: the SDK owns Wonderful builds, assets, manifests,
  budgets, and release policy; SwanSong remains the only gameplay backend.
- Prove the 0.3-to-0.4 Sparkle update on beta-enabled clients while stable-only
  clients remain on their selected channel and private library/project data is
  preserved.
- Developer ID sign, notarize, staple, Gatekeeper-assess, and inspect the
  universal Apple silicon and Intel archive from its exact release tag.
- Publish corresponding source, checksums, manifest, release notes, beta guide,
  and the matching repo-backed Wiki revision.
- Keep the Homebrew Catalog **Coming Soon** and network-silent and keep the
  separate SwanSong Core release lane locked until its independent gates pass.
- Retain Open IPL, controller, save/state, portrait, accessibility,
  minimum-macOS, A/V soak, Translation Lab, and local-MCP regression coverage.

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
