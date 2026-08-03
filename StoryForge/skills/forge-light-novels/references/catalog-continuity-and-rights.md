# Catalog, Continuity, Rights, and Soundtrack

## Schema migration and lockfiles

Schema 3 adds explicit evidence for scene delivery, continuity, reader
synthesis, illustration-set review, rights, accessibility, catalogs, and music.
Never edit a schema-2 manifest in place by hand merely to satisfy the new
number. Run:

```bash
python3 scripts/migrate_light_novel_project.py novels/<slug>/novel.json
```

The default writes `novel.v3.json` and leaves the source untouched. `--in-place`
creates a deterministic schema-v2 backup and refuses to overwrite an existing
backup. Migration cannot invent rights decisions, continuity, or human review;
its pending fields are deliberate.

After final reports, art, and music evidence are recorded, run:

```bash
python3 scripts/lock_light_novel_project.py novels/<slug>/novel.json
python3 scripts/lock_light_novel_project.py novels/<slug>/novel.json --check
```

The lockfile records the manifest, manuscript files, framework tree, referenced
reports, art, music, and available publication tools. Runtime paths are
diagnostic; story and evidence hashes determine staleness. Regenerate the lock
after any intentional final change. Do not use it to hide unreviewed edits.

## Continuity state ledger

Use typed entities for `time`, `location`, `costume`, `injury`, `object`,
`promise`, `relationship`, `knowledge`, and general `condition` state. Every
entity has one initial state, zero or more events, and one final state. Events
follow scene order and record:

- stable event and entity IDs;
- the scene where the change occurs;
- exact before and after states;
- concrete scene evidence for the cause or reveal.

The `before` value must equal the prior resolved state. Series volumes carry
important final states into the next volume's initial ledger. The report catches
declared contradictions; it cannot notice a continuity fact the team forgot to
declare. During continuity review, explicitly ask about wardrobe, handedness,
injury limits, object ownership, promises, knowledge asymmetry, location, and
elapsed time.

## Scene-delivery review

For every manuscript scene, a reviewer compares drafted evidence with the
planned `turn`, `decision`, `consequence`, `chemistry_move`, signature moment,
and rhythm-map `exit_pull`. Each dimension is `delivered`, `revised`, or
deliberately `waived`, and cites a concrete manuscript quote. A waiver also
states why removing or relocating the beat improves the book.

This review prevents an outline from looking excellent while the drafted scene
quietly omits its dramatic work. It does not require literal outline wording;
the evidence should prove the effect, not keyword overlap.

## Reader-feedback synthesis

Keep every unprimed response intact. A separate human synthesis records:

- strongest consensus;
- meaningful disagreement rather than majority-rule erasure;
- genre expectation results, especially target-reader evidence;
- recurring confusion and skim patterns;
- recurring delight and tell-a-friend language;
- revision decisions;
- intentionally unchanged material and why.

Do not average taste. A polarizing scene may be the book's identity. Revise when
feedback reveals a broken promise, unclear causality, unintended reading, or
weak execution—not merely because one reader preferred another genre.

## Rights and release lanes

Every project chooses `original`, `fan-work`, or `licensed`, plus `private`,
`free-noncommercial`, or `commercial` release scope. Record the rights holder,
source franchises, attribution, restrictions, commercial-clearance status,
reviewer, and release statement.

A fan-work lane cannot pass as commercial. A licensed commercial lane requires
recorded approved clearance. Noncommercial status is not itself permission;
follow the current rights holder's published rules and obtain qualified advice
when risk or money is meaningful. This framework is a release-control record,
not legal advice or a license grant.

## Cross-novel originality and status

Run the catalog audit before approving a new premise slate and again before
release:

```bash
python3 scripts/audit_novel_catalog.py novels/
python3 scripts/status_novel_catalog.py novels/
```

The originality audit fails copied long-form prose and warns about unusually
similar premise language, relationship engines, endings, title vocabulary,
emotional rhythm, and illustration compositions. Review warnings as habits, not
automatic plagiarism verdicts. Recurring authorial signatures are allowed when
the book's specific dramatic engine and reader experience remain distinct.

The status tool writes JSON for automation and Markdown for humans. It does not
mutate projects. The dashboard reports declared stage, gate status, word/scene/
report/reader/art counts, stale evidence, and the next actionable issue.

## Optional soundtrack bible

Music is optional, never decorative debt. When enabled, define a master motif
and character, relationship, place, comedy, mystery, or emotional motifs. Each
motif states its hook, subject, emotional function, and transformation rule.
Each cue records:

- linked scenes and motifs;
- dramatic purpose and mood;
- BPM, meter, tonal center, hook, and loop bars;
- channel 1 lead, channel 2 bass, channel 3 harmony/sweep, and channel 4
  percussion/noise roles;
- one WonderSwan-specific feature and mono safety;
- optional companion or hardware-adaptation asset, hash, reviewer, and status.

Prefer a memorable, playful hook that changes meaning with the relationship or
story state. Validate loop seams, mono collapse, clipping, channel crowding, and
fatigue by listening. The report validates the declared plan and assets; it
cannot prove the music is fun.
