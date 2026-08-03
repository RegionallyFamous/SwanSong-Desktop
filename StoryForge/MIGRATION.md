# Story Forge monorepo migration

Story Forge moved into `RegionallyFamous/SwanSong-Desktop` on 2026-07-26.
`StoryForge/` is now the canonical source location for its framework, scripts,
skills, novels, games, ImageGen masters, runtime-ready art, music, documentation,
and current evidence.

The migration began from:

- repository: `https://github.com/RegionallyFamous/swansong-story-forge.git`;
- branch: `codex/story-forge-evidence-refresh`;
- base commit: `835d18d2794d04ed3d8c1a2783db06933ecee7c4`; and
- the complete live non-ignored working tree, including its uncommitted
  framework, game, art, audio, report, and documentation changes.

The former checkout is intentionally left untouched as a migration backup until
the SwanSong Desktop changes are reviewed and committed. New work belongs in
this directory. Do not split framework rules or game source back into a second
repository.

The migration also preserved the one previously verified
`mobile-suit-gundam-summary` candidate package named by its release evidence.
That candidate remains blocked by its three required human approvals; preserving
the package records its last verified state without promoting it to a public
release. Obsolete release archives were not imported.

The signed app does not carry the large game and evidence library. Its build
materializes a minimal `Contents/Resources/StoryForge` payload containing the
fixed desktop-invoked wrappers, the complete `forge-light-novels` skill, and a
per-file hash manifest. Personal manuscripts and production games remain local
source projects; ROMs, release archives, runtime mirrors, and stale evidence
remain ignored build artifacts.

## Migration verification

The integrated tree was verified in its new location with:

- every shippable game rebuilt, exhaustively played through SwanSong, packaged,
  and independently release-verified;
- the summary-game candidate validated through all 16 routes while retaining
  its human reader, music-listening, and physical-hardware approval blocks;
- Signal Before Dawn rebuilt reproducibly, checked through all 73 routes,
  persistence, audio soak, five visual codas, and save/load restoration, then
  packaged and independently verified;
- all 26 sprite-audition approvals converted to checkout-portable bindings;
- the complete Story Forge doctor, source-tree guards, installed skill mirrors,
  transition continuity, blink-family, audio, release-inventory, and stale
  evidence checks; and
- a fresh SwanSong Desktop app build with the included hash-manifested Story
  Forge framework.
