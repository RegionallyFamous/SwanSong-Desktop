# Swan Case Club

Short original WonderSwan Color light novel about two collectors, a tiny
club notebook, and a rainy-market cart with someone else's save file still
inside.

The graphics are built as WonderSwan-safe pixel art from the start:
224x144 backgrounds, 96x128 portrait sprites, 16-color WSC-style palettes,
and neutral/talk/blink character families.

## Build Assets And Project

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/swan-case-club/build_swan_case_club.py
```

## Build ROM

Use the generic game builder. It runs this game's asset/project generator,
copies the shared runtime into a game-local runtime, builds the ROM, and writes
the smoke/audit reports without overwriting Signal's generated evidence.

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/build_wscvn_game.py swan-case-club
```

The build is considered good only after the readiness, smoke, build, and audit
reports are `ok: true`:

```text
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/swan-case-club/reports/build-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/swan-case-club/reports/emulator-smoke-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/swan-case-club/reports/game-readiness-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/swan-case-club/reports/game-audit-report.json
```

## Open In Emulator

```bash
open -a /Applications/Mesen.app /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/swan-case-club/runtime-local/swan-case-club.wsc
```

## Package / Share Release

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/ship_wscvn_game.py swan-case-club
```
