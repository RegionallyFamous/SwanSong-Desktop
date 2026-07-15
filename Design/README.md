# SwanSong design direction

`SwanSong-UI-Direction.png` is an ImageGen-assisted composition study, not a
flattened asset used by the app. Its strongest ideas are implemented with real
SwiftUI controls: a visible source-list sidebar, a quiet empty state, a unified
toolbar, and restrained midnight/indigo/cyan accents.

`SwanSong-Library.png` and `SwanSong-Player.png` are focused ImageGen-assisted
studies made from the same brief. `SwanSong-Library-Populated.png` is a capture
of the running SwiftUI app using public test fixtures, so it can be used for
visual-regression comparison without confusing concept art with shipped UI.

## ImageGen brief

> Create a shippable, high-fidelity native macOS dark-mode interface for a
> focused WonderSwan emulator named SwanSong. Use real macOS window chrome, a
> source-list sidebar, unified toolbar, quiet hierarchy, generous spacing, and
> restrained midnight, indigo, and cyan accents. Keep the library and player
> uncluttered, use the supplied SwanSong icon as the brand anchor, and avoid
> dashboard cards, excessive glass, neon glow, mobile controls, and concept-art
> embellishment.

## Product rules

- Keep the shell recognizably macOS. Use system window chrome, source-list
  selection, toolbar overflow, menus, keyboard shortcuts, and Settings scenes.
- Put SwanSong's personality in the app icon, game library, player surface,
  and Translation Lab. Use SF Symbols for commands.
- Prefer spacing, typography, and separators to stacked blur, glow, border,
  material, and shadow treatments.
- Keep the sidebar hideable and resizable. Open Game belongs in File and the
  toolbar; Settings belongs in the application menu.
- Player controls live in the toolbar. Runtime status must fit at the minimum
  window width and communicate state with both a symbol and text.
- Empty states contain one title, one sentence, and one primary action.
- Test Dark, Light, Increase Contrast, Reduce Transparency, VoiceOver, Full
  Keyboard Access, 820/1040/1440-point widths, and inactive-window appearance.

## Apple references

- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/)
- [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)
- [ContentUnavailableView](https://developer.apple.com/documentation/swiftui/contentunavailableview)
