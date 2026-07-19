# Story Forge

Story Forge brings the schema-v3 light-novel framework into SwanSong as a
native writing and editorial desk. It can create novels, run stage gates,
refresh manuscript reports, manage a multi-book catalog, prepare ImageGen art,
check an optional soundtrack, and build EPUB/PDF editions without turning an
automated score into a claim that a book is good.

Story Forge remains the source of narrative policy and tools. SwanSong Desktop
provides the fixed, visible interface. This avoids a second story engine whose
rules could drift from the repository that owns the framework.

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

## Five workspaces

### Overview

Create a novella, short light novel, or full volume with a genre profile and
target length. The stage rail keeps Concept, Outline, Draft, Revision, and
Release distinct. Checking a later stage includes every earlier gate.

The overview keeps chapter, scene, reader, report, illustration, rights, and
soundtrack facts separate. A passing automated gate means the required evidence
is present and internally current. It does not replace an editor, unprimed
readers, or named human approval.

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

### Art & Music

**Create ImageGen Briefs** turns approved scene intentions into production
prompts. Every new or replacement cover, interior illustration, character
design, prop sheet, and location key starts in ImageGen. SwanSong does not draw
a placeholder when ImageGen art is missing.

**Review Illustration Set** verifies source provenance, current hashes,
composition, character and prop continuity, eye line, artifacts or accidental
lettering, must-show/must-avoid delivery, and the complete contact sheet.
Approval remains bound to the exact image set.

Music is optional. When enabled, the soundtrack report checks memorable hooks,
motif transformations, cue purpose, loop intent, mono safety, and the four
WonderSwan channel roles. The report can validate the declared evidence; a
person still decides whether the music is fun.

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
command field. Manuscripts, reports, art, music, lockfiles, dashboards, EPUBs,
and PDFs stay in the selected folders. Coarse local automation may report only
whether a Story Forge project is open and can navigate to the workspace. It
does not return a title, path, manuscript, report, image, music file, edition,
diagnostic text, or approval record.

Story Forge never invents a human reviewer or approval and never treats
programmatic art as production illustration.
