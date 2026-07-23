# Story Forge

Writing a novel is not a progress bar. Story Forge gives the whole process a
home—idea, outline, draft, revision, art, continuity, rights, and release—while
leaving taste and approval with actual people.

The native workspace can run a proposal-only Story Room, show causal and
Narrative Pulse maps,
edit chapters with live scene context, preserve revision branches, manage
unprimed readers plus live reaction bookmarks and research, prepare ImageGen
art, author music auditions, measure WonderSwan adaptation drift, prove story
delivery against exhaustive SwanSong evidence, manage a catalog, and build EPUB/PDF
editions without turning an automated score into a claim that a book is good.

Story Forge was introduced in SwanSong 0.5.0 and remains included in current
stable and beta releases.

Story Forge remains the source of narrative policy and tools. SwanSong Desktop
provides the fixed, visible interface. This avoids a second story engine whose
rules could drift from the repository that owns the framework.

## Why these tools exist

The repository's maintained
[light-novel quality standard](https://github.com/RegionallyFamous/swansong-story-forge/blob/main/skills/forge-light-novels/references/quality-standard.md)
records the product principles behind the workbench. The short version is:

- connected causes help events remain available in memory, so Pulse shows
  causal load and missing setup/payoff links;
- attention, affect, imagery, and character engagement matter, so Story Forge
  keeps human reader reactions instead of manufacturing a quality score;
- suspense depends on meaningful anticipation and concern, not arbitrary
  confusion, so open questions retain stakes and consequences; and
- music changes empathy and scene interpretation, so motif intent and native
  playback are checked together.

Those findings justify diagnostic questions, not a required emotional curve.
Every automated report remains subordinate to editors, real readers, players,
and named human approvals.

## Connect the framework

1. Open **Story Forge** under **Tools**.
2. Choose the swansong-story-forge repository. SwanSong requires its complete
   scripts folder, schema-v3 starter, and all current report tools.
3. Choose the folder that contains your novel projects.
4. Create a novel or open its dependency-free **novel.json**.

The selected framework, catalog, and manifest are remembered locally. SwanSong
does not scan the Mac for manuscripts or upload them. An explicit
**SWANSONG_STORY_FORGE_DIR** development override is available; the normal app
uses the folder selected in the interface.

## Nine workspaces

### Overview

Create a novella, short light novel, or full volume with a genre profile and
target length. The stage rail keeps Concept, Outline, Draft, Revision, and
Release distinct. Checking a later stage includes every earlier gate.

The overview keeps chapter, scene, reader, report, illustration, rights, and
soundtrack facts separate. A passing automated gate means the required evidence
is present and internally current. It does not replace an editor, unprimed
readers, or named human approval.

**Show Next Actions** reads the exact project and gives a short evidence-backed
queue instead of a generic checklist.

### Story Room

Prepare fresh packets for the premise scout, story architect, character editor,
continuity editor, prose editor, art director, music director, and release
editor. Every packet has the same project context, a bounded specialty, and a
proposal-only output contract. The human lead writer selects and merges work.

No specialist silently edits prose or canon, invents a reader, or approves art,
music, rights, or release evidence.

### Map & Draft

**Build Map** creates a browser-readable view of chapters, causal scene turns,
relationships, setups/payoffs, continuity, rhythm, illustrations, and music.
The native manuscript editor opens Markdown chapters, makes unsaved changes
visible, and saves only when asked. Choose a stable scene ID to refresh live
context: goal, pressure, turn, decision, consequence, adjacent scenes,
relationships, rhythm, art, music, and warnings.

**Build Pulse** adds load-bearing events, open reader questions, motif
appearances, and long stretches whose tension, warmth, humor, and wonder barely
change. It is a revision aid, not a required emotional curve or quality score.

Revision snapshots are immutable. Compare any named snapshot with the current
manuscript, then append an accept, partial, or reject decision and rationale to
the timeline. Existing decisions are never rewritten.

### Editorial

Run the complete suite or one report at a time:

- character voice;
- prose polish;
- chapter momentum and emotional rhythm;
- scene delivery;
- typed continuity;
- reader-feedback synthesis;
- rights and release; and
- soundtrack bible.

Reader synthesis preserves meaningful disagreement and deliberate non-changes.
It never averages taste into one score. Continuity tracks time, location,
costume, injury, objects, promises, relationships, knowledge, and conditions
through stable scene IDs.

### Readers & Research

Reader Lab exports a spoiler-free manuscript and neutral response form. It does
not prime readers with the outline or desired revision. Import requires the
current manuscript hash, a real reader identity, every answer, explicit local
storage consent, and a response that has not already been imported.

**Live Reader Moments** begins a manuscript-hash-bound session for a named real
reader. During or immediately after the read, preserve the scene and the
reader's own short note as laughed, moved, confused, paused, bored, or wanted
more. SwanSong keeps those moments separate and never turns them into an
average taste score. A manuscript change requires a fresh session.

The research notebook links sources to claims, claims to scenes, confidence,
sensitivity, and authenticity review. The genre specialist adds mystery clue
fairness, romance boundary and reciprocity, cozy sincerity, comedy escalation,
or adventure competence questions without flattening taste.

### Art & Music

**Prepare Art Room** assembles the visual contract, reference pack, moment queue,
and status. Prompt history is append-only. Every new or replacement cover,
interior illustration, character design, prop sheet, and location key starts in
ImageGen. SwanSong does not draw a placeholder when ImageGen art is missing.
Intake preserves the original image and prompt record, binds an exact hash, and
resets approval to pending.

**Review Illustration Set** verifies source provenance, current hashes,
composition, character and prop continuity, eye line, artifacts or accidental
lettering, must-show/must-avoid delivery, and the complete contact sheet.
Approval remains bound to the exact image set.

Music is optional. Music Room creates editable four-channel sketches, renders
two mono loops, and measures peak, RMS, duration, and seam delta. The soundtrack
report still checks hooks, motif transformations, cue purpose, loop intent,
mono safety, and WonderSwan roles. Generated notes are auditions; a person still
decides whether the exact music is fun.

### Adaptation

**Compile Scaffold** creates a `.wscvn.json` authoring project, source map, and
per-scene Story Proof contract that preserve novel scene IDs, turns, decisions, consequences, setups, payoffs,
and lossless 26×4 text pagination. It always says `production_ready: false`.
**Check Drift** exposes missing mappings, stale manuscript hashes, and possible
over-condensation after either source changes.

After the production project passes its exhaustive SwanSong playthrough,
choose that playthrough report and select **Prove Story Delivery**. Story Proof
checks each declared turn and consequence against the route that reached it,
accepted input, reachable next state, ImageGen presentation, effective motif,
presented-raster fade continuity, native audio, and captured ending where
required. The generated **Story Ribbon** is a readable checkpoint timeline.
It proves that a beat arrived in the running ROM; it does not prove that the
beat is well written or replace readers and editors.

Continue in Studio only begins the actual adaptation pass. Production still
requires authored VN beats and choices, approved ImageGen art, the novel
revision gate, WonderSwan readiness, and exhaustive SwanSong route, save/replay,
fade, and native-audio testing.

Long route matrices show a flushed `route-N (current/total)` line and retain
`wall_time_seconds` for every route. The Story Forge doctor terminates the whole
emulator process group on timeout, so a child player cannot survive and make a
failed test look like a silent hang. Its whole-game deadline scales from the
enumerated route count, within fixed safety bounds; long stories are not given
the same total wall-clock allowance as four-route stories.

### Catalog

Catalog Status shows every book's stage, words, scenes, reports, readers, art,
stale evidence, and next useful action. Originality Audit compares copied prose
and repeated premise, relationship, ending, rhythm, title, and composition
defaults. Similarity is a review lead rather than an automatic plagiarism
verdict.

Series Bible consolidates canon, volume promises, protected mysteries, future
hooks, and continuity between books.

### Publish

Rights & Release distinguishes original, fan-work, and licensed projects plus
private, free-noncommercial, and commercial scope. A fan-work project cannot
pass as commercial clearance; a licensed commercial release needs recorded
approval. This is workflow evidence, not legal advice.

The project lock freezes the exact manuscript, framework, reports, ImageGen
art, music, and publication environment. The release builder then creates
deterministic EPUB and PDF editions and checks accessibility metadata,
text-extraction parity, embedded fonts, every rendered PDF page, and external
EPUBCheck when installed or required. Open the all-page contact sheet before
approval.

Schema-v2 migration writes a separate v3 manifest by default and leaves rights,
continuity, and human decisions pending.

## WonderSwan handoff

After the Revision gate, **Continue in Studio** opens SwanSong Studio. Keep the
novel's stable scene IDs in the game project and carry over causality,
continuity, signature moments, relationship changes, ImageGen design rules, and
soundtrack motifs. A screen adaptation may condense prose, but it must not erase
the turn or consequence that made a scene necessary.

The game still passes Studio's build, deterministic SwanSong route, save/load,
audio, evidence, and release gates. Novel approval does not substitute for ROM
proof, and ROM proof does not substitute for novel approval.

## Safety and privacy boundary

SwanSong invokes only its typed Story Forge allowlist; there is no arbitrary
command field. Manuscripts, reports, role packets, maps, revisions, reader
responses, research, art, music, adaptations, lockfiles, dashboards, EPUBs, and
PDFs stay in the selected folders. Coarse local automation may report only
whether a Story Forge project is open and can navigate to the workspace. It
does not return a title, path, manuscript, report, image, music file, edition,
diagnostic text, or approval record.

Story Forge never invents a human reviewer or approval and never treats
programmatic art as production illustration.
