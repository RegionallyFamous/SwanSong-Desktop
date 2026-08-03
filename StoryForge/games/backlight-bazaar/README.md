# Backlight Bazaar

Short original WonderSwan Color light novel about two collectors finding a
rumored cart at a rainy retro-game market.

## Build Assets And Project

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/backlight-bazaar/build_backlight_bazaar.py
```

## Build ROM

Use the generic game builder. It runs this game's asset/project generator,
copies the shared runtime into a game-local runtime, builds the ROM, and writes
the smoke/audit reports without overwriting Signal's generated evidence.

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/build_wscvn_game.py backlight-bazaar
```

The build is considered good only after the readiness, smoke, build, and audit
reports are `ok: true`:

```text
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/backlight-bazaar/reports/build-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/backlight-bazaar/reports/emulator-smoke-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/backlight-bazaar/reports/game-readiness-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/backlight-bazaar/reports/game-audit-report.json
```

## Open In Emulator

```bash
open -a /Applications/Mesen.app /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/backlight-bazaar/runtime-local/backlight-bazaar.wsc
```

## Package / Share Release

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/ship_wscvn_game.py backlight-bazaar
```
