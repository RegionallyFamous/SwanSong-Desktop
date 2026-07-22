# Translation Lab

Translation work gets difficult when “this screen looks wrong” is the only
evidence you have. Translation Lab turns that feeling into something you can
replay, compare, review, and keep.

Link a private WonderSwan translation project and SwanSong can record the exact
route to a screen, replay it against Original and Patched, compare native
frames, find the first visual change, review visible text on-device, and keep
the evidence beside the project. The ROM never enters the normal game library.

## What you can do here

- record a deterministic test from clean boot;
- compare Original and Patched at the exact same frame;
- run a source-free matrix of case-specific diagnostic viewers;
- build a suite of routes and run them together;
- locate the first frame where the two builds diverge;
- turn reviewed on-screen text into a private translation draft;
- append bounded observed-play sequences, capture named checkpoints, and branch
  from a clean-boot-replayed prefix; and
- investigate a selected rectangle without sending private source addresses
  or cartridge lineage through automation.

## Workspace and readiness

Open **Translation Lab** in the sidebar and choose **Add Translation Project…**,
or drag a project, `project.json`, or private toolkit folder into the window.
Adding a toolkit discovers its immediate projects. The project switcher keeps
each game's status, routes, captures, and reviews separate.

Toolkit status is presented as a structured readiness dashboard with corpus
coverage, pipeline phases, and explicit next actions. Commands suggested by a
project are shown for reference but are never run automatically.

Every action that can reach Strict Pack uses one fail-closed sequence:

1. fresh Status;
2. QA;
3. validation;
4. Strict Pack; and
5. final Status.

PENDING is allowed before a project's first pack. BLOCKED, UNKNOWN, malformed
output, or a failed command stops before mutation. The linked project identity
is pinned across asynchronous stages, and every successful Status re-indexes
route, evidence, baseline, and suite history so externally changed artifacts
cannot keep a stale integrity label.

## Translation Surface Suite

The **Translation Surface Suite** is the certification layer above ordinary
route captures. A title-specific toolkit builder remains responsible for
creating diagnostic viewer ROMs. SwanSong imports only a source-free
`swan-song-translation-surface-suite-v1` manifest and owns generic execution,
native review, and the final evidence handoff.

Each stable case ID binds:

- a family name and exact Original and Patched diagnostic ROM byte counts and
  SHA-256 digests;
- one bounded `swan-song-frame-input-plan-v1` file and digest;
- one or more strictly ordered named checkpoints;
- exact expected Original and Patched native game-raster hashes at every
  checkpoint; and
- one or more native-pixel rectangles where change is allowed.

Import validates every project-contained file before execution. Absolute,
escaping, symlinked, changed, oversized, and `.partial-*` paths fail closed.
The selected ABI must match both the manifest and SwanSong's bundled ares
engine.

**Run Suite** creates a new deterministic engine session for each case and each
lane, always using clean power-on, empty isolated persistence, Open IPL, and the
fixed proof RTC. A single replay can capture several named screens. A case
fails automatically when either endpoint hash is wrong, the pixel delta is
zero, orientation or dimensions drift, or any pixel outside the declared
change regions changes. Pixel difference is still only a review target.

Progress is saved after every case. **Resume Failed** rehashes the retained
artifacts for every passing case and re-runs only failed or damaged cases from
clean boot. Once all machine assertions pass, SwanSong writes an immutable
execution report and opens the stable-ID review queue.

The queue presents Original, Patched, blink, and difference views at exact
native 1×. Reviewers record separate Semantic, Functional microcopy, and Visual
fit verdicts. Condensed rendering must be flagged and approved explicitly, and
audio must be marked observed with no issue. No visual or audio hash approves
itself.

**Create Final Certificate** rehashes every stable evidence path, rejects
staging paths, requires all review dimensions and audio observations, and
writes one immutable `swan-song-translation-surface-certification-v1` report.
The handoff includes engine identity, ABI, coverage counts, endpoint and change-
region results, native image and audio paths/digests, and the exact review
sidecars.

## Deterministic route tests

Choose **Record a Test…** from the Translation menu. SwanSong cold-launches
the Original image with empty isolated persistence, fixes the emulated RTC at
`2000-01-01T00:00:00Z`, and arms recording before the first frame. Normal
library play continues to use the Mac's clock.

At the target screen, choose **Save at Frame N**, use **Save Test Case at This
Frame…**, or press Option-Command-R. Name the route and optionally add a review
note. **Verify Selected Route** then runs the guarded build sequence and replays
the exact route against Original and Patched outputs.

New routes use `swan-song-input-route-v3`. Each route binds:

- source ROM digest and byte count;
- clean-power-on and empty-isolated-persistence policy;
- WonderSwan model and Open IPL identity;
- engine backend and build;
- deterministic RTC mode and seed;
- target frame and compact input changes; and
- a canonical native game-raster checkpoint.

Replay rejects any changed execution context. Route-v2 files remain visible
with a **v2 · Re-record RTC** badge because they did not bind RTC policy.
Route-v1 files remain visible with a **v1 · Re-record** badge because their
starting state is unknowable. Neither version is silently upgraded or accepted
as deterministic evidence.

## Captures and paired review

A capture writes the native emulator framebuffer PNG together with its
game-raster fingerprint, internal RAM, engine state, route, and SHA-256-bound
manifest. These artifacts remain under `analysis/swan-song-lab/` in the linked,
ignored private project.

Original and Patched captures pair only when they share the same immutable
route digest. The evidence desk supports:

- Side-by-Side review;
- opacity-controlled Overlay;
- Difference heatmap;
- exact 1×, 2×, and 4× pixel zoom; and
- changed-pixel count, percentage, channel deltas, and bounds.

Comparison metrics exclude the 13-pixel WonderSwan hardware-icon strip and all
macOS player chrome, scaling, display profiles, and LCD effects. A visual
change is a review target, not an automatic failure.

Reviews are mutable project-local sidecars with Unreviewed, Approved, and
Needs Work verdicts plus notes. Changing a review never rewrites the immutable
capture manifest.

## Capture and Draft Translation

Choose **Extract Source Text…** from an intact capture. Full Frame and Dialogue
Band provide keyboard-accessible region presets; a pointer can draw a tighter
rectangle.

Apple Vision recognition runs on-device and is always treated as a draft. The
reviewer corrects or manually enters only visible source text, confirms each
line, then saves the intake before drafting target-language text.

SwanSong writes deterministic private sidecars:

- `text-intake.json` records reviewed text, pixel bounds, quantized confidence,
  and the capture hash; and
- `translation-draft.json` binds the exact intake bytes by SHA-256, keeps source
  IDs/text immutable, permits unfinished target lines, and records manual entry
  and review state.

Neither file embeds screenshot pixels, filesystem paths, ROM data, timestamps,
cloud requests, generated-translation claims, or unreviewed OCR output. The
source intake is evidence of reviewed visible text, not a glyph-table or ROM-
pointer claim. The draft is manual user-authored target text and does not alter
the ROM.

## Batch verification

**Run All Cases** performs the guarded build sequence once, then advances
through every proof-ready route and captures fresh Original/Patched endpoints.
A legacy route blocks the suite until it is re-recorded from boot.

Completed runs are immutable project-local `suite-runs` reports with exact
route/evidence references and changed-versus-identical counts. The UI keeps
overall progress and the current case visible, and completed history survives
relaunch.

## First Visual Change

**First Visual Change** replays Original and Patched with identical inputs,
fixed RTC, and empty isolated persistence. It first confirms that Original
still reaches the recorded endpoint, then locates the earliest changed
canonical game-raster frame.

The single-instance engine is respected through sequential deterministic
passes. Only compact Original fingerprints are retained during the search.
When a difference is found, SwanSong briefly reconstructs the exact Original
frame and opens the native comparison desk. **Create Test at This Frame** saves
a new immutable, event-filtered route prefix for focused regression testing.

This process never enters the normal library and never writes its cartridge
saves, save states, or ROMs.

## RAM inspection and pointer leads

The paired evidence desk includes a private checkpoint-RAM inspector with:

- changed ranges;
- bounded search;
- ASCII and Shift-JIS text-buffer analysis; and
- bounded Pointer Leads.

Pointer Leads identifies 16-bit little-endian RAM values matching changed
text-buffer addresses, classifies stable/added/removed reference sites, and
jumps to the corresponding Bytes row. These are heuristic debugging leads,
not proof of a ROM pointer or bank.

## Source-free diagnostics

**Export Source-Free Diagnostic…** creates a `.swsdiag` package from an
allowlist: rendered frame, verified input route, hashes, metadata, and saved
review. The exporter never opens or copies ROM, boot ROM, RAM, save-state, or
cartridge/console-save bytes.

RAM, decoded text, pointer reports, captures, draft artifacts, and project paths
remain private project analysis. Do not attach them to public issues.

## Automation and tests

The signed app includes a deterministic `SwanSongRouteRunner`. Its legacy form
replays an existing route and rejects route-bound identity drift. Four guarded
project-writing commands close the autonomous evidence and diagnosis gaps:

- `capture-plan` records and verifies a plan, then privately persists the exact
  plan, both native endpoints, deterministic context bindings, and pixel diff
  as one immutable pair;
- `probe-rectangle` replays one role to an exact plan frame and privately saves
  per-pixel layer, map-cell, tile/raster, palette, sprite/OAM, and CPU-writer
  provenance, while its report exposes only hashes and counts;
- `record-route` converts a versioned frame/input plan into route-v3 using
  Original, empty isolated persistence, the fixed proof RTC, and a native
  endpoint checkpoint; and
- `verify-pair` runs the route against Original and Patched, captures both
  native endpoints, runs Capture Intake twice, re-indexes both immutable
  manifests, and returns their bound identities.

All four route/capture commands require `--enable-debug-tools` and
`--allow-project-writes`. Inputs and optional report outputs must remain inside
the project. Two additional guarded commands, `probe-rectangle-source` and
`export-static-analysis-seed`, keep bounded cartridge lineage and analyzer
anchors private while returning only source-free receipts. All six are exposed
by the opt-in local MCP server with an explicit `confirmProjectWrites`
argument. Full schemas, commands, privacy
boundaries, and failure behavior are in [[Local MCP and Automation]].

The MCP server also supports one retained observed-play session for long
tactical sequences. A single step or a bounded multi-event sequence atomically
extends a private from-boot plan; sequences can return selected named
checkpoints. A branch creates a new active route only after replaying its saved
prefix from clean boot. If the MCP host exits, Resume Observed Play validates
the private bindings and replays that plan from boot before accepting another
step. Finishing unloads the live session and sends that exact plan through
`capture-plan`; live state or a save-state shortcut is never accepted as final
evidence.

The Evidence page also indexes these durable automation artifacts separately
from ordinary checkpoint captures. It verifies paired captures, private
display-owner probes, and observed sessions; reports their local size and
integrity; can reveal or safely delete an inactive artifact; and exports a
source-free JSON summary without frames, map/tile/palette sources, or writer
identities. A low-disk warning appears before the hard safety reserve is
reached, and every new durable artifact runs a free-space preflight.

Translation Lab, Pocket Challenge V2, differential, route-runner, and
focus/input test commands are documented in [[Build and Test]].
