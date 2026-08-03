---
name: forge-light-novels
description: Plan, outline, draft, critique, revise, and release distinctive light novels with reusable story bibles, causal scene plans, manuscript lint, editorial scorecards, reader-test evidence, and stage-gated quality reports. Use when Codex is asked to brainstorm or research novel premises, create a story bible or cast, turn an idea into chapters, write or expand a light novel, diagnose repetitive or filler-heavy fiction, revise character voice or pacing, adapt a visual-novel script into stronger prose, build a repeatable novel pipeline, or decide whether a manuscript is ready for illustration, WonderSwan adaptation, or release.
---

# Forge Light Novels

## Purpose

Build novels through a repeatable creative and editorial pipeline. Protect
specificity, causality, voice, escalation, payoff, and emotional residue before
optimizing word count or adaptation assets.

Never claim that an automated score proves a novel is excellent. Use automation
to expose omissions and suspicious repetition; require evidence-backed editorial
judgment and a real reader approval for release.

## Start Here

1. Identify the requested stage: `concept`, `outline`, `draft`, `revision`, or
   `release`.
2. For a new project, run:

   ```bash
   python3 scripts/create_light_novel_project.py <slug> --title "Title"
   ```

   When using the installed skill outside Story Forge, call the copy under this
   skill's `scripts/` directory directly.
   Migrate a schema-v2 project without overwriting it:

   ```bash
   python3 scripts/migrate_light_novel_project.py novels/<slug>/novel.json
   ```
   For an existing WonderSwan project, begin with an advisory migration audit:

   ```bash
   python3 scripts/audit_wscvn_story_prose.py games/<slug>/projects/<slug>.wscvn.json --advisory
   ```
3. Read `references/quality-standard.md` before selecting a premise, expanding a
   draft, or evaluating quality.
4. Read `references/project-format.md` before creating or changing `novel.json`
   or a YAML equivalent.
5. Read `references/delight-and-genre.md` before outlining signature moments,
   emotional rhythm, relationship chemistry, or a genre-specific pleasure.
6. Read `references/editorial-passes.md` before a `revision` or `release` gate.
7. Read `references/publication-and-illustration.md` before commissioning art or
   building an EPUB/PDF.
8. Read `references/catalog-continuity-and-rights.md` before managing multiple
   novels, continuity ledgers, release rights, or optional soundtracks.
9. Read `references/story-room-and-workbench.md` before using the Story Room,
   revision branches, Reader Lab, Art Room, Music Room, or WonderSwan bridge.
10. Read `references/genre-specialists.md` when a mystery, romance, cozy/comedy,
   or adventure manuscript needs specialist judgment.
11. Ask the command center for the next useful action:

   ```bash
   python3 scripts/forge.py next novels/<slug>/novel.json
   ```
12. Validate the current stage:

   ```bash
   python3 scripts/check_light_novel_project.py novels/<slug>/novel.json --stage outline
   ```

## Stage Gates

### Concept

- Generate a premise slate before selecting the book. Compare at least five
  candidates by hook, relationship engine, story engine, ending pressure, and
  derivative risk; use ten when developing a series or batch.
- Define a concrete reader promise, hook, emotional question, thematic
  argument, comic or dramatic engine, desired aftertaste, originality
  boundaries, non-goals, and the signature question only this novel can answer.
- Select a genre profile. Satisfy its expected pleasures, then state a freshness
  move and forbidden shortcuts so genre fluency does not become imitation.
- Establish a standalone or series contract: volume promise, arc position,
  continuity, canon, protected mysteries, and future hooks.
- Give every major character an external want, internal need, false belief,
  vulnerability, contradiction, behavioral tell, and voice pattern.
- Define relationships as changing pressure systems, not static biographies.
- Reject interchangeable premises and stories that depend only on licensed
  recognition or a one-line gag.

### Outline

- Build chapters from scene cards. Every scene needs a goal, pressure, turn,
  decision, consequence, entering state, and changed exit state.
- Connect scenes with explicit `because_of` causality. Do not outline a chain of
  unrelated “and then” events.
- Plant setups and pay them off with changed meaning. Track evolving motifs
  separately from repeated wording.
- Make comedy escalate or reveal character; do not use jokes to cancel every
  sincere beat.
- Plan at least one signature moment per chapter. A signature moment may be
  funny, surprising, tender, wondrous, competent, recognizable, or cathartic;
  never turn this into a joke quota.
- Map tension, warmth, humor, and wonder by scene to expose accidental emotional
  sameness while preserving surprise. Give each scene a chemistry move and a
  reader-facing question or pull.
- Lock an illustration bible with character, location, prop, composition, and
  continuity rules. Generate briefs before production images.
- Maintain a typed continuity state ledger for time, place, costume, injury,
  objects, promises, relationships, and knowledge. Every declared transition
  must name its before/after state and scene evidence.
- A soundtrack is optional. If enabled, plan character/place/emotional motifs,
  fun loop hooks, cue purpose, BPM, meter, tonal center, channel roles, and a
  WonderSwan-specific feature before producing audio.
- Pass the outline gate before commissioning production illustrations or
  expanding the manuscript.

### Draft

- Draft to scene intent, not a global word-count expander.
- Mark each manuscript scene with `<!-- scene: scene-id -->` and preserve the
  outline order unless the outline is deliberately revised first.
- Give paragraphs physical action, sensory evidence, thought, or consequence.
  Remove generic connective prose that could appear in any story.
- Mark representative character samples with `<!-- voice: character-id -->` so
  the voice fingerprint report can compare evidence without rewriting prose.
- Run the draft gate. Investigate every duplicate sentence, repeated long
  phrase, placeholder, missing scene, and unusual scene-length outlier.

### Revision

- Read `references/editorial-passes.md` and complete each pass separately.
- Record issue evidence, the change made, and verification in the revision
  ledger. “Polished” is not evidence.
- Score each quality category from 1–5 with scene-specific evidence and an
  honest remaining risk. Require at least 4 in every category; never average a
  weak ending away with strong formatting.
- Use unprimed readers who were not responsible for the current draft. Record
  their strongest moment, confusion, expectation, delight, skim points, favorite
  line/image, tell-a-friend description, next-volume appetite, and the revision
  response. Require both a general reader and an intended-audience reader by
  default.
- Run the voice, prose, chapter-momentum, scene-delivery, continuity,
  reader-synthesis, and rights reports. Add the soundtrack report when music is
  enabled. Treat warnings as leads, record an editorial response, and bind each
  report to the manuscript hash.
- Synthesize reader evidence as consensus, meaningful disagreement, genre
  expectation, confusion, delight, revision decisions, and deliberate
  non-changes. Never average taste into a single score.
- Run the cross-novel originality audit and record a human catalog decision.
  A one-book catalog establishes a baseline; rerun when another manuscript
  enters revision.

### Release

- Re-run all prior gates against the exact final manuscript.
- Require completed developmental, causality, character-voice, comedy/tone,
  chemistry/delight, continuity/payoff, line-prose, read-aloud, and publication
  polish passes.
- Require resolved critical ledger items, a reader test, and explicit human
  approval. An AI may prepare the evidence but must not invent a human name or
  approval.
- Require ImageGen provenance, approved prompts, approved art, and exact asset
  hashes for every cover and interior illustration. Programmatic art is allowed
  only for clearly labeled test fixtures, never production art.
- Review the complete art set on a contact sheet. Check composition variety,
  character and prop continuity, eye line, accidental lettering/artifacts, and
  must-show/must-avoid delivery. Bind per-image and set approval to asset hashes.
- Confirm the original, fan-work, or licensed lane. A fan-work lane cannot be
  treated as commercial clearance; this workflow records decisions but does not
  provide legal advice.
- Freeze the framework, manuscript, reports, art, and music evidence in
  `novel.lock.json`, then build and inspect both EPUB and PDF outputs.
- Require accessibility metadata, text-extraction parity, embedded fonts, every
  PDF page rendered into a contact sheet, and external EPUBCheck when the
  project marks it required.

## Adaptation

- Treat `novel.json` plus the manuscript as narrative source of truth.
- For a WonderSwan version, invoke `$build-wonderswan-vn` only after the outline
  gate; require at least the revision gate before calling the game finished.
- Preserve scene IDs through adaptation so story evidence maps to VN nodes.
- Condense prose for the screen without erasing causal turns, setup/payoff, or
  ending residue.
- Use ImageGen for every new or replacement production illustration. Generate
  art only after the relevant scene purpose and emotional beat are locked.
- Compile a traceable authoring scaffold with `forge.py adapt`, then run
  `adaptation-drift` after either source changes. The compiler preserves scene
  IDs and uses the shared 26×4 text paginator, but always marks its output as a
  non-production scaffold until `$build-wonderswan-vn` and SwanSong gates pass.
- Run `forge.py story-pulse` while outlining and revising. Treat causal load,
  open questions, motif appearances, and flat rhythm runs as diagnostic leads,
  never as a formula or quality score.
- A terminal invitation to the reader may declare
  `reader_question_status: intentional-open`; Story Pulse then preserves it
  without misreporting it as a missing setup/payoff answer. Use this only for a
  deliberate ending aperture, never to excuse an abandoned plot question.
- Keep ImageGen assets mechanically distinct from human approval:
  `approved-runtime-master` may record the accepted production file, while
  `approval_status` and the set review remain explicitly pending until a named
  human art director reviews the hash-bound contact sheet.
- When a scored novel already has an authored WonderSwan adaptation, set
  `soundtrack_bible.adaptation_project` to its repository-relative project
  file and give each cue an `adaptation_track_id`. `forge music-init` then
  imports the exact tempo, current `lengthSteps`, held notes, channel waves,
  muted PCM reservation, and source hash instead of inventing a short generic
  loop. The imported score still requires subjective listening approval.
- Keep the generated Story Proof contract aligned with the production VN. After
  exhaustive SwanSong playtesting, run `forge.py story-proof` so each authored
  turn and consequence is tied to a reached runtime node, accepted input,
  reachable next state, approved art state, effective motif, smooth fade,
  native audio, and ending capture where applicable.

## Story Room

- When the user explicitly asks for the Story Room team, load
  `references/story-room-and-workbench.md`, generate fresh packets, and delegate
  only bounded specialist roles when parallel agents are available.
- The premise scout, architect, character editor, continuity editor, prose
  editor, art director, music director, and release editor return proposals
  with evidence. The human lead writer alone selects and merges changes.
- Never let a role silently mutate prose, canon, reader records, art approval,
  music approval, or release status.

## Art and Music Rooms

- Use ImageGen for every new or replacement production image. Keep append-only
  prompt history, source images, exact hashes, audition notes, and full-set
  contact-sheet review. If ImageGen is unavailable, report the blocker; never
  substitute procedural scene art.
- Use the Music Room for editable cue sketches and two-loop mono auditions.
  Treat generated notes as compositional proposals. For device music, invoke
  `$make-wonderswan-music`, verify native audio in SwanSong, and preserve exact
  audio approval evidence.
- Use live Reader Lab bookmarks to preserve exactly where a named reader
  laughed, felt moved, paused, became confused or bored, or wanted more. Bind
  sessions to the manuscript hash and preserve the reader's note verbatim.

## Non-Negotiable Quality Rules

- Do not lengthen fiction with shuffled stock sentences, repeated observations,
  duplicated callbacks, or paraphrased filler.
- Do not let every character share the narrator's syntax and metaphors.
- Do not resolve a conflict merely because the target word count was reached.
- Do not hide a weak middle behind multiple endings or decorative lore.
- Do not mark editorial passes complete without evidence and changes.
- Preserve authorial intent. Suggest alternatives when a quality rule conflicts
  with a deliberate effect; document an explicit waiver instead of silently
  normalizing the work.

## Bundled Tools

- `scripts/forge.py`: fixed-contract command center for next actions, Story
  Room, maps, live scene context, revision branches, Reader Lab, research,
  genre specialists, ImageGen provenance, music auditions, WonderSwan
  adaptation, drift, validation, and bounded watch mode.
- `scripts/forge_workbench.py`: reusable workbench services and versioned JSON
  report contracts consumed by the CLI and SwanSong Desktop.
- `scripts/wscvn_adaptation.py`: source-mapped non-production VN compiler and
  novel/game drift report; it also emits a per-scene Story Proof contract draft.
- `scripts/wscvn_story_proof.py`: validates authored Story Proof checkpoints
  against exhaustive SwanSong route, input, fade, audio, and ending evidence,
  then builds the visual Story Ribbon.

- `scripts/create_light_novel_project.py`: copy the starter into a new project
  with stable IDs and configurable scale.
- `scripts/check_light_novel_project.py`: validate structure, manuscript
  coverage, causality, setup/payoff, repeated prose, editorial evidence, and
  release approval.
- `scripts/audit_wscvn_story_prose.py`: expose repeated sentences, phrases, and
  stock connective prose in a legacy `.wscvn.json` before migration.
- `scripts/report_character_voice.py`: build evidence-backed voice fingerprints
  from hidden manuscript sample markers.
- `scripts/report_prose_polish.py`: report filter phrases, clichés, weak
  modifiers, repeated openings, and rhythm leads without auto-deleting voice.
- `scripts/report_chapter_momentum.py`: verify scene rhythm, chapter hooks, and
  signature-moment coverage.
- `scripts/report_scene_delivery.py`: compare each scene's drafted evidence with
  its turn, decision, consequence, chemistry, signature, and exit-pull promises.
- `scripts/report_novel_continuity.py`: resolve the typed state ledger and expose
  mismatched before/after or final states.
- `scripts/synthesize_reader_feedback.py`: preserve reader consensus,
  disagreement, confusion, delight, and revision decisions without averaging.
- `scripts/report_rights_release_lane.py`: audit original, fan-work, and licensed
  release boundaries as a workflow guard.
- `scripts/report_soundtrack_bible.py`: validate optional motifs, fun hooks,
  WonderSwan channel plans, loop intent, assets, and approvals.
- `scripts/make_imagegen_illustration_briefs.py`: turn the illustration bible
  into production-ready ImageGen prompt sheets.
- `scripts/review_novel_illustrations.py`: build a review-only contact sheet and
  validate hash-bound image and set approvals.
- `scripts/build_series_bible.py`: consolidate volume promises, canon, arcs,
  protected mysteries, and future hooks across `novels/`.
- `scripts/audit_novel_catalog.py`: compare books for copied prose and repeated
  premise, relationship, ending, rhythm, title, and composition defaults.
- `scripts/status_novel_catalog.py`: produce JSON and Markdown dashboards with
  stages, counts, stale evidence, approvals, and the next useful action.
- `scripts/migrate_light_novel_project.py`: migrate schema v2 to v3 safely.
- `scripts/lock_light_novel_project.py`: create or check the deterministic
  evidence and framework lockfile.
- `scripts/build_novel_release.py`: build deterministic EPUB and typeset PDF
  editions; run EPUBCheck when available, compare extracted text, inspect font
  embedding, and render every PDF page plus a complete contact sheet.
- `assets/starter/`: canonical project, manuscript, and reader-test templates.
- `references/quality-standard.md`: creative quality contract and anti-filler
  rules.
- `references/project-format.md`: manifest fields and stage semantics.
- `references/editorial-passes.md`: revision roles, scorecard evidence, and
  reader-test protocol.
- `references/delight-and-genre.md`: signature moments, rhythm, chemistry,
  target-reader enjoyment, reader enjoyment evidence, and genre profiles.
- `references/publication-and-illustration.md`: ImageGen provenance,
  illustration continuity, publication metadata, EPUB/PDF, and series bibles.
- `references/catalog-continuity-and-rights.md`: schema migration, lockfiles,
  catalog originality/status, continuity, rights lanes, and soundtrack bibles.
- `references/story-room-and-workbench.md`: proposal-only team rules, fixed
  reports, revision/reader/research/art/music rooms, and adaptation.
- `references/genre-specialists.md`: mystery fairness, romance boundaries,
  comedy escalation, cozy rhythm, and adventure competence.
- `assets/story-room-roles.json`: canonical eight-role specialist contracts.

YAML manifests are supported when PyYAML is available to the active interpreter
or another standard local Python discovered by the tools. JSON remains the
dependency-free canonical format.
