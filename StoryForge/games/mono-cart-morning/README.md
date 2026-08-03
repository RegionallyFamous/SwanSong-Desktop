# Mono Cart Morning

Short original WonderSwan Color light novel about two collectors deciding what
a flea-market WonderSwan haul should become: a perfect shelf, a play log, or a
shared lending case.

## Build Assets And Project

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/mono-cart-morning/build_mono_cart_morning.py
```

## Build ROM

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/build_wscvn_game.py mono-cart-morning
```

Expected outputs:

```text
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/mono-cart-morning/projects/mono-cart-morning.wscvn.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/mono-cart-morning/runtime-local/mono-cart-morning.wsc
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/mono-cart-morning/reports/build-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/mono-cart-morning/reports/emulator-smoke-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/mono-cart-morning/reports/game-readiness-report.json
/Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/mono-cart-morning/reports/game-audit-report.json
```

## Open In Emulator

```bash
open -a /Applications/Mesen.app /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/games/mono-cart-morning/runtime-local/mono-cart-morning.wsc
```

## Package / Share Release

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/ship_wscvn_game.py mono-cart-morning
```

Manual fallback after a fresh build:

```bash
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/package_wscvn_game.py mono-cart-morning
python3 /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge/scripts/verify_wscvn_game_release.py mono-cart-morning
```
