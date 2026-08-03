# Light Novel Project Format

## Files

```text
novels/<slug>/
├── novel.json
├── novel.lock.json
├── manuscript/
├── art/
├── music/
├── editorial/
│   ├── reader-test.md
│   └── imagegen-illustration-briefs.json
├── reports/
│   ├── character-voice-report.json
│   ├── prose-polish-report.json
│   ├── chapter-momentum-report.json
│   ├── scene-delivery-report.json
│   ├── continuity-report.json
│   ├── reader-synthesis-report.json
│   ├── rights-release-report.json
│   ├── soundtrack-bible-report.json
│   ├── illustration-set-review.json
│   ├── illustration-review/contact-sheet.png
│   └── publication-proof/all-pages-contact-sheet.png
├── workbench/
│   ├── story-room.json
│   ├── story-map.json
│   ├── story-map.html
│   ├── revisions/
│   ├── reader-packets/
│   ├── reader-responses/
│   ├── art-room/
│   ├── music-room/
│   ├── adaptation/
│   └── research-notebook.json
└── output/
    ├── epub/
    └── pdf/
```

`novel.json` is the dependency-free canonical manifest. YAML is accepted when
PyYAML is available. All project paths must remain under the project root.

## Schema version 3

Top-level fields:

- `schema_version`: `3`.
- `stage`: `concept`, `outline`, `draft`, `revision`, or `release`.
- `framework`: profile/version contract and lockfile path.
- `workbench`: optional schema-1 configuration for the human lead writer,
  proposal-only merge policy, local reader privacy, ImageGen-only art policy,
  Story Room roles, research, music, and WonderSwan adaptation.
- `rights_release`: original, fan-work, or licensed lane; release scope,
  attribution, restrictions, clearance, and review.
- `identity`, `development`, and `creative_contract`: reader promise, premise
  slate, selection, hook, theme, engine, aftertaste, and originality boundaries.
- `genre_profile`: expected pleasures, freshness move, forbidden shortcuts, and
  scene-bound deliveries.
- `series`: volume promise, arc position, continuity, canon, protected
  mysteries, and hooks.
- `continuity_ledger`: typed initial states, scene events, and final states.
- `soundtrack_bible`: optional motifs, cue briefs, WonderSwan channel roles,
  loop intent, assets, and approvals.
- `cast`, `relationships`, `chapters`, `scenes`, `setups`, `motifs`, and
  `delight`.
- `illustration_bible`: design continuity, ImageGen moments, per-image reviews,
  and full-set approval.
- `manuscript`, `publication`, `quality`, and `editorial`.

Use `migrate_light_novel_project.py` for schema 2. The default writes a new v3
file; `--in-place` preserves a schema-2 backup. Migration intentionally leaves
rights, continuity, and human-review decisions pending.

All stable IDs use lowercase letters, digits, and hyphens. Do not use array
positions as durable identity.

Mutable workbench material is not release evidence by default. Add exact,
finalized project-relative paths to `framework.workbench_evidence` when they
must be included in `novel.lock.json`; never lock a whole scratch directory.

## Scenes, continuity, chemistry, and delight

Every scene names POV, participants, location, time, goal, pressure, turn,
decision, consequence, changed state, causality, setup/payoff IDs, sensory and
specific imagery, tonal move, chemistry move, reader question, and target words.
Every chapter has an opening hook and closing pull. Every relationship includes
status, friction, shared joke, secret tenderness, dialogue tactics, and status
flips.

`delight.signature_moments` records setup, delivery, desired effect, and why the
moment belongs only to this book. `delight.rhythm` covers every scene in order
with tension, warmth, humor, wonder, entry hook, and exit pull. It exposes
sameness; it is not an ideal waveform or joke quota.

The continuity ledger uses entities of type `time`, `location`, `costume`,
`injury`, `object`, `promise`, `relationship`, `knowledge`, or `condition`.
Every event's `before` must equal the prior resolved state. Its `after` must
change and cite scene evidence. Every entity has a final state.

## Manuscript markers

Start each scene with `<!-- scene: scene-01 -->`. Mark representative character
samples with `<!-- voice: protagonist -->`. The validator joins Markdown files
in lexical order and hashes filename plus bytes. Publication output removes
hidden comments.

## Illustration and publication

Each illustration moment records scene, role, narrative purpose, emotional
beat, composition, must-show/must-avoid, continuity references,
`source_method: imagegen`, prompt status, asset path/hash, approval, and reviewer.
Production art and revisions always use ImageGen. Programmatic imagery is
allowed only in explicitly labeled framework tests.

Every release image adds an `art_review` bound to the current asset hash. Its
checklist covers composition, character consistency, continuity, eye line,
artifacts/lettering, must-show, and must-avoid. `set_review` binds the full
contact sheet, report, set-level findings, and approval to the ordered asset-set
hash.

`publication.accessibility` records summary, features, hazards, reviewed alt
text, and reviewed reading order. `publication.print` records trim/bleed intent.
`require_external_epubcheck` makes absence or failure of EPUBCheck a release
error. PDF preflight checks all-page rendering, text parity, font embedding, and
the declared trim; EPUB preflight checks package structure, accessibility
metadata, extracted text, and EPUBCheck when installed.

## Editorial evidence

`editorial.reviewed_manuscript_sha256` binds revision evidence to the exact
draft. Required reports are:

- `character-voice`, `prose-polish`, and `chapter-momentum`;
- `scene-delivery`, `continuity`, `reader-synthesis`, and `rights-release`;
- `soundtrack-bible` when music is enabled.

Every report entry stores a safe path, exact report SHA-256, manuscript SHA-256,
and reviewer response. Every pass records reviewer, scene-specific evidence,
and changes. Scorecard items use a 1–5 score, evidence, and remaining risk.

`scene_delivery_reviews` covers the planned turn, decision, consequence,
chemistry move, signature moment, and exit pull for every scene with an accepted
status and evidence quote. `reader_feedback_synthesis` preserves consensus,
meaningful disagreement, genre expectations, confusion, delight, revision
decisions, and intentionally unchanged material. Never average reader taste.
`catalog_originality_review` binds the exact manuscript and catalog audit to a
human findings/decision record; it is required for release.

## Stage semantics

- `concept`: creative, genre, series, framework, and rights contracts.
- `outline`: causal scenes, continuity, delight/rhythm, optional soundtrack,
  and illustration plans.
- `draft`: complete scene-marked manuscript and repetition checks.
- `revision`: passes, all required reports, ledger, scorecard, reader tests, and
  feedback synthesis.
- `release`: human approval, ImageGen asset and set review, accessibility,
  current lockfile, publication preflight, and no unresolved critical issue.

Validation includes every earlier stage. A later stage never bypasses prior
evidence.

## Commands

```bash
python3 scripts/forge.py next novels/<slug>/novel.json
python3 scripts/forge.py story-room novels/<slug>/novel.json
python3 scripts/forge.py story-map novels/<slug>/novel.json
python3 scripts/forge.py scene-context novels/<slug>/novel.json --scene scene-01
python3 scripts/forge.py genre-report novels/<slug>/novel.json
python3 scripts/forge.py art-room novels/<slug>/novel.json
python3 scripts/forge.py music-init novels/<slug>/novel.json
python3 scripts/forge.py adapt novels/<slug>/novel.json
python3 scripts/migrate_light_novel_project.py novels/<slug>/novel.json
python3 scripts/check_light_novel_project.py novels/<slug>/novel.json --stage revision
python3 scripts/report_character_voice.py novels/<slug>/novel.json
python3 scripts/report_prose_polish.py novels/<slug>/novel.json
python3 scripts/report_chapter_momentum.py novels/<slug>/novel.json
python3 scripts/report_scene_delivery.py novels/<slug>/novel.json
python3 scripts/report_novel_continuity.py novels/<slug>/novel.json
python3 scripts/synthesize_reader_feedback.py novels/<slug>/novel.json
python3 scripts/report_rights_release_lane.py novels/<slug>/novel.json
python3 scripts/report_soundtrack_bible.py novels/<slug>/novel.json
python3 scripts/make_imagegen_illustration_briefs.py novels/<slug>/novel.json
python3 scripts/review_novel_illustrations.py novels/<slug>/novel.json
python3 scripts/lock_light_novel_project.py novels/<slug>/novel.json
python3 scripts/build_series_bible.py novels/
python3 scripts/audit_novel_catalog.py novels/
python3 scripts/status_novel_catalog.py novels/
python3 scripts/build_novel_release.py novels/<slug>/novel.json
```

Any nonzero exit means the requested evidence or artifact is not ready.
