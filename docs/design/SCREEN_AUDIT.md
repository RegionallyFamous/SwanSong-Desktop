# SwanSong Desktop screen audit

This is the visual QA checklist for the native macOS app. It records the July 2026 screen-by-screen pass and keeps future changes aligned with the same product language.

## Direction

- Native macOS controls and behavior come first.
- Neutral system surfaces carry the interface; blue identifies SwanSong, violet identifies Translation Lab, and cyan identifies Studio and Pocket tools.
- Important screens have one clear focal action. Supporting information is quieter and grouped into consistent recessed, standard, or elevated surfaces.
- Light and Dark appearances are equal products, not a primary theme and a fallback.
- Dense diagnostic screens keep their information density, but use stronger headings, spacing, and panel ownership.

The ImageGen direction board used during this pass is a design reference only. The shipped interface remains native SwiftUI rather than rasterized mockup UI.

## Screen coverage

| Screen family | Reviewed states | Result |
| --- | --- | --- |
| App shell and sidebar | Light, Dark, compact, wide, current selection | Branded header, calmer grouping, and consistent navigation rhythm |
| Library | Empty, populated, selected, inspector, compatibility states | Stronger cards, clearer selected state, welcoming first-run action |
| Homebrew | Coming soon, privacy disclosure, loading, unavailable, catalog | Consistent first-run panels and clearer trust/action hierarchy |
| Translation Lab | Empty, overview, routes, text intake, drafting, evidence, visual divergence, RAM inspection | Violet ownership, stronger project hierarchy, consistent evidence surfaces |
| SwanSong Studio | SDK setup and workspace shell | Welcoming setup state and cyan tool identity without losing native behavior |
| Analogue Pocket | Core setup and progress steps | Clear task sequence and better safety-note hierarchy |
| Play and recovery | Horizontal, vertical, stalled-picture recovery, rewind | Deliberately dark player canvas with compact, readable recovery controls |
| Save states | Timeline, selection, resume actions | Semantic cards and clearer chronology |
| Settings | Display and Player, Controller, Updates | Consistent grouping, readable state, and native control behavior |
| Support | Support navigation and formatted content | Structured headings and readable sections instead of unformatted source text |

## Regression gate

The deterministic gallery renders 88 images across Light and Dark appearances: 58 core views, 12 Homebrew views, and 18 focused-polish views. Perceptual hashes catch hierarchy or theme regressions while structural checks catch blank content, unsupported controls, clipping, and low-information renders. Support formatting also has a dedicated structured-document render check because its production copy is bundled at packaging time.

When a screen changes intentionally, inspect both appearances before refreshing the reviewed baselines.
