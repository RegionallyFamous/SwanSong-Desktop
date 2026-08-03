# Reusable Light Novel Framework

Story Forge’s schema-v3 framework develops prose-first books, strengthens visual
novel stories, and prepares narrative source packages for WonderSwan adaptation.
It keeps creative, reader, continuity, visual, music, rights, and publication
evidence separate while joining them at explicit stage gates.

The primary-source rationale for Narrative Pulse, Live Reader Lab, Story Proof,
motif music, and consequence-forward interludes is recorded in
[Story-quality research and product response](story-quality-research.md). The
research is used to generate revision questions, never a universal quality
score.

## Create or migrate

```bash
python3 scripts/create_light_novel_project.py tea-at-platform-zero \
  --title "Tea at Platform Zero" \
  --genre-profile cozy-comedy \
  --series-id platform-zero

python3 scripts/migrate_light_novel_project.py novels/older-book/novel.json
```

The migration default writes `novel.v3.json` without changing schema v2. Its
pending rights, continuity, and review fields are deliberate; migration never
invents human decisions.

JSON is canonical. YAML is supported when PyYAML is available. Scales are
12,000-word short light novel, 25,000-word novella, and 50,000-word volume, with
an explicit target override.

## The Story Room workbench

The reusable workbench adds eight proposal-only specialists: premise scout,
story architect, character editor, continuity editor, prose editor, art
director, music director, and release editor. The human lead writer chooses and
merges their proposals. No specialist silently rewrites prose or invents an
approval.

```bash
python3 scripts/forge.py next novels/<slug>/novel.json
python3 scripts/forge.py story-room novels/<slug>/novel.json
python3 scripts/forge.py story-map novels/<slug>/novel.json
python3 scripts/forge.py story-pulse novels/<slug>/novel.json
python3 scripts/forge.py scene-context novels/<slug>/novel.json --scene scene-01
```

The same fixed JSON reports drive SwanSong Desktop. The Story Map joins causal
scenes, setup/payoff, relationships, continuity, rhythm, illustration moments,
and music cues. Revision snapshots never overwrite each other; decisions are
append-only. Reader Lab exports unprimed packets and refuses incomplete, stale,
anonymous, or unconsented imports. The research notebook links sources to
claims, scenes, confidence, sensitivity, and authenticity review.

The Narrative Pulse map adds causal load, open reader questions, motif
appearances, and flat rhythm runs. These are revision leads, not a universal
shape or quality score. Live Reader Lab sessions can also preserve the exact
scene where a named reader laughed, felt moved, paused, became confused or
bored, or wanted more; sessions are bound to the manuscript hash.

Art Room maintains ImageGen prompt history, source files, exact hashes,
auditions, and full-set review. Applying a new ImageGen result always resets its
approval. Music Room creates editable four-channel sketches and renders two
mono loops with peak, RMS, and seam diagnostics; generated notes remain
auditions until a person approves them.

## The five gates

### Concept

Choose from at least five premise candidates—or ten for batch/series work—and
lock the reader promise, signature question, genre pleasures, freshness move,
series contract, cast voices, and relationship engines.

Declare `rights_release` as `original`, `fan-work`, or `licensed`, plus
`private`, `free-noncommercial`, or `commercial` scope. Record ownership,
source franchises, attribution, restrictions, clearance, reviewer, and release
statement. A fan-work lane cannot pass as commercial. This is a workflow guard,
not legal advice.

### Outline

Every scene has goal, pressure, turn, decision, consequence, changed state,
chemistry move, reader question, and causal parent. Chapters add opening hooks
and closing pulls. Genre expectations point to payoff scenes. Signature moments
and tension/warmth/humor/wonder rhythm expose sameness without creating a joke
quota.

Maintain a typed continuity ledger for time, location, costume, injury, object,
promise, relationship, knowledge, and conditions. Before/after states and scene
evidence must resolve into exact final states.

The illustration bible locks design, acting, prop, location, palette, lighting,
and composition rules. Every production moment uses `source_method: imagegen`.

Music is optional. When enabled, the soundtrack bible defines a master motif,
character/place/comedy/mystery/emotional motifs, cue purpose, memorable hooks,
BPM, meter, tonal center, loop bars, WonderSwan channels 1–4, mono safety, and a
hardware-specific feature.

### Draft

Mark scenes with `<!-- scene: scene-01 -->` and representative voice samples
with `<!-- voice: protagonist -->`. The gate checks coverage, order, scene
length, completeness, placeholders, repeated paragraphs/sentences/long phrases,
banned language, and known filler. New length must come from pressure, reversal,
decision, reaction, or consequence.

### Revision

Generate all required evidence:

```bash
python3 scripts/report_character_voice.py novels/<slug>/novel.json
python3 scripts/report_prose_polish.py novels/<slug>/novel.json
python3 scripts/report_chapter_momentum.py novels/<slug>/novel.json
python3 scripts/report_scene_delivery.py novels/<slug>/novel.json
python3 scripts/report_novel_continuity.py novels/<slug>/novel.json
python3 scripts/synthesize_reader_feedback.py novels/<slug>/novel.json
python3 scripts/report_rights_release_lane.py novels/<slug>/novel.json
python3 scripts/report_soundtrack_bible.py novels/<slug>/novel.json
```

Scene-delivery evidence compares each draft with its planned turn, decision,
consequence, chemistry, signature moment, and exit pull. Reviewers cite a quote
and mark each dimension delivered, revised, or deliberately waived.

Use at least one unprimed general reader and one intended-audience reader.
Synthesis preserves consensus, meaningful disagreement, genre expectations,
confusion, delight, revision decisions, and intentional non-changes. It never
averages taste.

Complete nine editorial passes, a 15-part scorecard with scene evidence, a
revision ledger, a human-reviewed catalog originality audit, and hash-bound
reviewer responses for every report.

### Release

Create ImageGen prompt sheets, generate every production image with ImageGen,
and review the complete set:

```bash
python3 scripts/make_imagegen_illustration_briefs.py novels/<slug>/novel.json
python3 scripts/review_novel_illustrations.py novels/<slug>/novel.json
```

Per-image approval checks composition, character/prop continuity, eye line,
artifacts/lettering, must-show, and must-avoid. The set review inspects one
contact sheet for repeated compositions and consistency. Image and set verdicts
are hash-bound. Programmatic imagery is allowed only in labeled tests, never as
production art.

After final human approval, freeze the evidence and publish:

```bash
python3 scripts/lock_light_novel_project.py novels/<slug>/novel.json
python3 scripts/lock_light_novel_project.py novels/<slug>/novel.json --check
python3 scripts/build_novel_release.py novels/<slug>/novel.json
```

The lock covers the manifest, manuscript, framework, reports, art, and music.
The builder produces deterministic EPUB/PDF editions, checks accessibility
metadata, extracted-text parity, font embedding, and print intent, renders every
PDF page, and builds a complete contact sheet. External EPUBCheck runs when
installed and is a hard requirement when the manifest says so.

## Catalog and series tools

```bash
python3 scripts/build_series_bible.py novels/
python3 scripts/audit_novel_catalog.py novels/
python3 scripts/status_novel_catalog.py novels/
```

The series bible rejects volume-number and canon conflicts. The originality
audit fails copied long prose and flags repeated premise, relationship, ending,
rhythm, title, and illustration-composition defaults for human judgment. The
status dashboard writes JSON and Markdown with stage, counts, stale evidence,
approvals, and next action without mutating projects.

## WonderSwan handoff

Keep the schema-v3 manifest and manuscript as narrative source of truth and
preserve scene IDs in `.wscvn.json`. Pass outline before production art and
revision before calling an adaptation finished. Use `build-wonderswan-vn` for
pagination, conversion, authored music, SwanSong route testing, and release.
Condensation may shorten prose but must preserve turns, consequences,
setup/payoff, chemistry, signature moments, continuity, and ending residue.

Start with a traceable, explicitly non-production scaffold and measure drift:

```bash
python3 scripts/forge.py adapt novels/<slug>/novel.json
python3 scripts/forge.py adaptation-drift novels/<slug>/novel.json \
  --project novels/<slug>/workbench/adaptation/<slug>.wscvn.json
python3 scripts/forge.py story-proof novels/<slug>/novel.json \
  --project path/to/production.wscvn.json \
  --contract path/to/production.story-proof.contract.json \
  --playthrough path/to/swansong-playthrough-report.json
```

The compiler uses the shared 26-column by 4-line paginator and writes a source
map from novel scene IDs to VN nodes. Production readiness still requires
authored VN beats, ImageGen production art, the novel revision gate,
`build-wonderswan-vn`, and exhaustive SwanSong playtesting.

The adaptation compiler also writes a per-scene Story Proof contract draft.
Production completes each checkpoint with route variants, reachable next
states, approved visual presentation, motif music, fade requirements, and
ending evidence. Story Proof then binds those intentions to the exhaustive
SwanSong input/node trace, native audio, presented-raster fade profiles, and
captured endings. Its visual Story Ribbon shows delivery at a glance without
claiming that runtime evidence proves literary quality.

Exhaustive playthroughs print a flushed `route-N (current/total)` boundary and
store `wall_time_seconds` per route. Doctor timeouts terminate the complete
emulator process group, preventing an orphaned child player from turning a
bounded failure into a silent hang. The full-game deadline scales from the
enumerated route count, with bounded minimum and maximum values, so a healthy
27-route story is not killed by a deadline intended for a four-route game.

## Verification and maintenance

```bash
python3 scripts/selftest_light_novel_framework.py
python3 scripts/selftest_forge_workbench.py
python3 scripts/check_forge_light_novels_skill.py --require-installed-match
python3 scripts/doctor_story_forge.py
git diff --check
```

The self-test covers migration, all five gates, cross-report/manuscript hashes,
scene delivery, continuity, reader synthesis, rights, music, ImageGen-only art
provenance, full-set art review, lock staleness, catalog originality/status,
EPUB/PDF text parity, embedded fonts, every-page proofing, and post-approval
changes.

The workbench self-test covers all eight role packets, visual and Narrative
Pulse maps, live scene context, revision snapshots/diffs/decisions, reader
export/import refusal, live Reader Lab bookmarks, research and genre reports,
ImageGen provenance intake, mono two-loop music, WonderSwan source maps/drift,
Story Proof contracts, and bounded watch mode.

## Checked-in reference novel

`examples/reference-novel/` contains the complete six-scene original story
*The Last Tea Home* and a deterministic reference builder. It exercises the
Story Room, map, scene context, research, genre, ImageGen Art Room, music
auditions, adaptation bridge, and draft gate:

```bash
python3 examples/reference-novel/build_reference.py /tmp/story-forge-reference
```

The reference deliberately leaves real readers, ImageGen production assets,
art-set review, revision approval, and release approval pending. A trustworthy
example demonstrates those blockers instead of counterfeiting green evidence.

For a legacy visual novel, run `audit_wscvn_story_prose.py --advisory` before
migrating the narrative. Advisory mode exposes repetition without pretending an
old game already satisfies schema-v3 evidence.
