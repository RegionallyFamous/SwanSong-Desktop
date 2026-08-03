# Soft Click Sunday

Short original WonderSwan Color VN about collecting fictional WonderSwan carts.

## Build Assets And Project

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/soft-click-sunday/build_soft_click_sunday.py
```

## Build ROM

Use the generic game builder. It runs this game's asset/project generator,
copies the shared runtime into a game-local runtime, builds the ROM, and writes
the smoke/audit reports without overwriting Signal's generated `runtime-local`
evidence.

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/build_wscvn_game.py soft-click-sunday
```

The build is considered good only after the readiness, smoke, build, and audit
reports are `ok: true`:

```text
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/soft-click-sunday/reports/build-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/soft-click-sunday/reports/emulator-smoke-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/soft-click-sunday/reports/game-readiness-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/soft-click-sunday/reports/game-audit-report.json
```

## Open In Emulator

```bash
open -a /Applications/Mesen.app /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/soft-click-sunday/runtime-local/soft-click-sunday.wsc
```

## Package / Share Release

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/ship_wscvn_game.py soft-click-sunday
```

Manual fallback after a fresh build:

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/package_wscvn_game.py soft-click-sunday
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/verify_wscvn_game_release.py soft-click-sunday
```
