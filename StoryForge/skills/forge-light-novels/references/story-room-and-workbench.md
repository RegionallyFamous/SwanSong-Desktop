# Story Room and Workbench

## Operating Model

The Story Room is a set of independent editorial viewpoints, not a committee
that rewrites the book. Each role receives the same project evidence plus a
bounded specialty packet. It returns findings and proposals with scene or
manifest evidence. The human lead writer selects, combines, rejects, or asks
for another pass.

When a user explicitly asks to use the Story Room team, agents may delegate
the bounded role packets in parallel. Give each agent one named role, require
proposal-only output, and keep manuscript mutation with the lead writer. Do
not delegate the final merge, fabricate reader reactions, or ask an agent to
approve art it did not inspect.

Generate fresh packets with:

```bash
python3 scripts/forge.py story-room novels/<slug>/novel.json
```

The eight canonical roles live in `assets/story-room-roles.json`: premise
scout, story architect, character editor, continuity editor, prose editor, art
director, music director, and release editor.

## Workbench Contract

`novel.json` and the manuscript remain narrative source of truth. The
`workbench/` directory contains derived maps, proposal packets, reader forms,
revision snapshots, research notes, art prompt history, music auditions, and
adaptation evidence. Mutable workbench material is not release approval.

Every workbench report has fixed top-level fields:

- `schema_version` and `workbench_schema_version`
- `tool`, `ok`, `errors`, and `warnings`
- manifest path/hash and manuscript hash
- a `facts` object specific to the command
- explicit artifact paths when files were produced

Desktop clients must invoke the fixed `forge.py` command family. They must not
construct shell pipelines, accept arbitrary executable paths, or infer success
from console text alone.

## Daily Commands

```bash
python3 scripts/forge.py next novels/<slug>/novel.json
python3 scripts/forge.py story-map novels/<slug>/novel.json
python3 scripts/forge.py story-pulse novels/<slug>/novel.json
python3 scripts/forge.py scene-context novels/<slug>/novel.json --scene scene-01
python3 scripts/forge.py revision-snapshot novels/<slug>/novel.json --name before-middle-pass
python3 scripts/forge.py revision-compare novels/<slug>/novel.json --left before-middle-pass
python3 scripts/forge.py genre-report novels/<slug>/novel.json
python3 scripts/forge.py release novels/<slug>/novel.json
```

`watch` is intentionally a bounded polling helper by default. Use
`--cycles 0` only in an interactive terminal and stop it explicitly.

## Reader Lab

Reader packets are spoiler-free: they include the manuscript, a neutral form,
and no outline rationale or desired revision outcome. Import refuses a stale
manuscript hash, blank identity, incomplete answers, or missing local-storage
consent. Imported responses are stored separately and never overwritten.

Preserve disagreement in synthesis. Two readers wanting different versions of
the book is editorial information, not a score to average away.

For an in-person or screen-shared read, create a hash-bound live session and
record the moment plus the reader's own note without priming later readers:

```bash
python3 scripts/forge.py reader-lab-init novels/<slug>/novel.json \
  --session live-reader-01 --reader "Reader Name"
python3 scripts/forge.py reader-bookmark novels/<slug>/novel.json \
  --session live-reader-01 --scene scene-04 --signal laughed \
  --note "The attempted formal greeting broke the tension."
```

Signals are `laughed`, `moved`, `confused`, `paused`, `bored`, and
`wanted-more`. Sessions become stale when the manuscript hash changes.

## Revision Branches

Revision snapshots are immutable copies beneath `workbench/revisions/`.
Comparisons create unified diffs. Decisions append to `decisions.jsonl`; they
do not silently replace earlier choices. A snapshot name can never be reused.

## Research and Authenticity

The notebook links sources to claims, claims to scenes, confidence, sensitivity,
and authenticity reviews. A URL alone is not a claim. A claim without a source
remains unverified. Cultural, lived-experience, medical, or legal material needs
an explicit authenticity-review link when it influences published prose.

## Art Room

The Art Room is ImageGen-only for new and replacement production art. It
maintains the visual contract, reference pack, moment queue, append-only prompt
history, preserved source images, hashes, audition status, and full-set review.
`art-intake` requires provenance that explicitly names ImageGen. Applying an
intake updates the asset path/hash but resets approval to pending.

If ImageGen is unavailable, leave the moment blocked. Never create procedural,
vector-primitive, or code-painted fallback scene art.

## Music Room

Music sketches are editable four-channel auditions. The preview renderer uses
mono, renders two loops, and reports peak, RMS, and seam delta. Generated notes
are compositional starting points, not automatic approval. For a WonderSwan
release, follow `$make-wonderswan-music` and validate native playback in
SwanSong.

## Adaptation Bridge

`adapt` creates a traceable `.wscvn.json` authoring scaffold plus a source map.
It losslessly paginates text through the shared 26-column by 4-line helper and
preserves scene IDs, turns, decisions, consequences, setups, and payoffs in the
map. It is always labeled `production_ready: false` until authored VN beats,
ImageGen production art, the novel revision gate, WonderSwan readiness, and
exhaustive SwanSong playtesting pass.

Run `adaptation-drift` after either source changes. Stale manuscript hashes,
missing mappings, or extreme condensation remain visible rather than being
silently accepted.

`adapt` also creates a per-scene Story Proof contract. During production,
complete its route variants, ImageGen-approved art state, effective music cue,
transition, reachable next state, and runtime evidence requirements. After the
exhaustive SwanSong playthrough passes, build a hash-bound report and visual
Story Ribbon:

```bash
python3 scripts/forge.py story-proof novels/<slug>/novel.json \
  --project path/to/<slug>.wscvn.json \
  --contract path/to/<slug>.wscvn.story-proof.contract.json \
  --playthrough path/to/swansong-playthrough-report.json
```

Story Proof establishes delivery, not literary excellence. A passing
checkpoint means the authored beat was reachable and its declared presentation
evidence arrived in the running ROM; human editorial and reader judgment remain
separate gates.
