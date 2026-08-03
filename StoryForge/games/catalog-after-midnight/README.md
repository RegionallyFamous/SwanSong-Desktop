# Catalog After Midnight

Short original WonderSwan Color light novel about rescuing and cataloging a
closing repair shop's box of WonderSwan games.

## Build Assets And Project

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/catalog-after-midnight/build_catalog_after_midnight.py
```

## Build ROM

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/build_wscvn_game.py catalog-after-midnight
```

Expected outputs:

```text
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/catalog-after-midnight/projects/catalog-after-midnight.wscvn.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/catalog-after-midnight/runtime-local/catalog-after-midnight.wsc
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/catalog-after-midnight/reports/build-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/catalog-after-midnight/reports/emulator-smoke-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/catalog-after-midnight/reports/game-readiness-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/catalog-after-midnight/reports/game-audit-report.json
```

## Open In Emulator

```bash
open -a /Applications/Mesen.app /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/catalog-after-midnight/runtime-local/catalog-after-midnight.wsc
```

## Package / Share Release

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/ship_wscvn_game.py catalog-after-midnight
```

Manual fallback after a fresh build:

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/package_wscvn_game.py catalog-after-midnight
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/verify_wscvn_game_release.py catalog-after-midnight
```
