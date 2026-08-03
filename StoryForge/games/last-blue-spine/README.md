# The Last Blue Spine

Short original WonderSwan Color light novel about collecting fictional
WonderSwan games.

## Build Assets And Project

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/last-blue-spine/build_last_blue_spine.py
```

## Build ROM

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/build_wscvn_game.py last-blue-spine
```

Expected outputs:

```text
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/last-blue-spine/projects/last-blue-spine.wscvn.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/last-blue-spine/runtime-local/last-blue-spine.wsc
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/last-blue-spine/reports/build-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/last-blue-spine/reports/emulator-smoke-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/last-blue-spine/reports/game-readiness-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/last-blue-spine/reports/game-audit-report.json
```

## Open In Emulator

```bash
open -a /Applications/Mesen.app /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/last-blue-spine/runtime-local/last-blue-spine.wsc
```

## Package / Share Release

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/ship_wscvn_game.py last-blue-spine
```

Manual fallback after a fresh build:

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/package_wscvn_game.py last-blue-spine
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/verify_wscvn_game_release.py last-blue-spine
```
