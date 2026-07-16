# Design asset provenance

This directory is design history, not a press kit.

| Asset | Origin | Public-use status |
| --- | --- | --- |
| `SwanSong-UI-Direction.png` | ImageGen-assisted composition study | Concept only; not shipped UI |
| `SwanSong-Library.png` | ImageGen-assisted composition study | Concept only; not a screenshot |
| `SwanSong-Player.png` | ImageGen-assisted composition study | Concept only; not a screenshot |
| `SwanSong-Library-Populated.png` | Running SwiftUI app with public fixtures | Regression/reference only; diagnostic names and warning state make it unsuitable as a hero |
| `Design/AppIcon-Zine-Source.png` | ImageGen-assisted original directed for SwanSong; generated July 15, 2026 with the prior project icon used only as a concept reference | Project source master; no third-party source artwork |
| `Packaging/AppIcon.png` | Production resize and alpha mask derived from `Design/AppIcon-Zine-Source.png` | Shipped 1024px master and Dock artwork |
| `Packaging/AppIconCompact.png` / `AppIcon.icns` | Deterministic crop, palette simplification, and macOS iconset derived from `Packaging/AppIcon.png` by `Scripts/generate-app-icons.sh` | Shipped compact/menu and Finder artwork |

Launch screenshots must be captured from the running app with open-source or
clean-room fixtures. Record the app version, fixture license, capture date, and
any crop or color adjustment beside each future press asset.

Two design studies containing commercial-title imagery were deliberately
removed before the repository's public launch and are not project assets.
