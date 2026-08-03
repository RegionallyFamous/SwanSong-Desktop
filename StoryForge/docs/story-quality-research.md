# Story-quality research and product response

Research snapshot: **2026-07-22**

This note records the evidence behind Story Forge's narrative tools and the
SwanSong features that can make a prose story more memorable, playful, and
reliably adapted. It is a design record, not a formula for declaring a story
good. Automated reports expose questions for writers, editors, readers, and
players; they do not replace their judgment.

## Findings worth building around

| Finding | What the evidence supports | Story Forge response | Important limit |
|---|---|---|---|
| Causally and semantically central events are remembered better. | Naturalistic audiovisual narrative studies found better recall for events with stronger causal or semantic connections; a preregistered follow-up replicated the network-memory relationship. Work on nonlinear narrative also found that causal and chronological relationships organize recall more strongly than presentation order alone. | Narrative Pulse reports causal load and missing links. Scene plans retain a goal, turn, decision, consequence, causal parent, and setup/payoff relationships. | Centrality predicts a memory tendency, not literary merit. Quiet or deliberately peripheral scenes can still be essential. Pulse must remain diagnostic and must not optimize every scene toward equal centrality. |
| Transportation involves attention, affect, and imagery, and characters materially shape it. | Narrative-transportation research treats absorption as more than comprehension: attention, emotional response, and vivid character imagery all contribute. Experiments also show stronger capture by an intact, contiguous narrative than by the same scenes out of order. | Story Map keeps character goals, pressure, relationships, signatures, and causal adjacency together. Live Reader Lab records the exact scene where a real reader laughed, felt moved, paused, became confused or bored, or wanted more. | Transportation evidence is often retrospective, context-dependent, and studied in persuasion or film settings. Story Forge uses it to ask better reader questions, not to promise a particular response. |
| Suspense needs emotionally significant anticipation, not merely hidden information. | Reviews and experiments distinguish uncertainty or curiosity from suspense. Tension also depends on conflict or instability, a desire for resolution, future-directed expectation, and concern about the outcome. Readers can feel suspense even when they know an ending. | Scene plans retain open reader questions, pressure, stakes, and consequences. Pulse exposes questions that never receive a payoff. Reader bookmarks can identify anticipation that worked or stalled. | More uncertainty is not automatically more suspense. The framework must not reward arbitrary withholding, confuse confusion with curiosity, or require suspense in every genre and scene. |
| Music changes the interpretation of a scene. | Controlled studies found that melancholic and anxious scores changed empathy, perceived personality, environmental tone, plot anticipation, vigilance, and attention to details while the visual scene stayed fixed. Emotional music can also be a strong memory cue. | Music cues declare a dramatic purpose and motif transformation. Story Proof verifies that the intended cue actually played on the route and checkpoint. Music Room auditions loops and preserves human approval. | A technically present or memorable cue can still be tonally wrong. Native SwanSong audio evidence proves delivery, while a person decides whether it is fun and dramatically appropriate. |
| Coherent interaction should express the story's main verb and consequence. | This is an applied design inference from the narrative evidence and from the WonderWitch Grand Prix review, whose most legible games organize their other systems around one memorable action and complete front-to-back flow. | Adaptations can use short consequence-forward interludes: the player's action must change story state, feedback, or route understanding, and failure must progress rather than trap the reader. Exhaustive SwanSong routes prove every declared target can finish. | A mini-game added only for variety can break pacing. Interludes are optional and must serve character, pressure, or consequence rather than impersonate depth with points. |

## Product decisions implemented from the research

### Narrative Pulse, not an emotional-curve grader

`forge.py story-pulse` creates JSON and a browser-readable report containing:

- events with unusually high causal load;
- reader questions and the scenes that answer them;
- motif appearances; and
- long runs where declared tension, warmth, humor, and wonder barely move.

These are revision leads. There is no required curve, target number of peaks,
or automatic claim that a story is engaging.

### Live Reader Lab, not synthetic readers

`reader-lab-init` binds a named real reader's session to the exact manuscript
hash. `reader-bookmark` preserves a scene, one of six simple reaction signals,
and the reader's own note. If the manuscript changes, the session becomes stale
instead of silently attaching old reactions to new prose.

### Story Proof and Story Ribbon

The adaptation compiler writes a per-scene proof contract that retains turns,
decisions, consequences, relationships, setup/payoff, visual moments, and music
cues. After an exhaustive SwanSong playthrough, Story Proof verifies the
running ROM delivered each declared checkpoint with accepted input, a reachable
next state, fade continuity, native audio, and ending capture where required.
The Story Ribbon presents that evidence as a readable timeline.

Story Proof answers "did the cartridge deliver this beat?" It does not answer
"was the beat beautifully written?"

### SwanSong Desktop workspace

The native Story Forge interface now exposes Build Pulse, Live Reader Moments,
Prove Story Delivery, and the Story Ribbon without adding a second narrative
engine. The Desktop passes fixed arguments to the repository-owned tools and
shows their hash-bound results.

### Pilot: *Guntank Takes the Stairs*

The pilot declares eight proof checkpoints across four completed routes. Its
first choice is a consequence-forward playable interlude, its route variants
earn distinct landings, its second choice carries the theme into the outcome,
and four authored music cues cover arrival, effort, ascent, and ending residue.
The release lane rejects the package if Story Proof is incomplete or stale.

All production visuals remain ImageGen-derived. Presented-raster fade checks,
blink checks, accepted-input traces, reachable-next-state checks, captured
endings, and native-audio evidence protect the mistakes that a source-file
review cannot see.

## Current SwanSong and SDK capability audit

The public Desktop release reviewed for this snapshot is
[SwanSong 0.7.2](https://github.com/RegionallyFamous/SwanSong-Desktop/releases/tag/v0.7.2),
app identity **0.7.2 (15)**. Its Translation Lab can bind capture to qualified
ABI 9 or ABI 10 engine profiles, while preserving the existing strict
capability and engine-match boundary.

The latest public SDK release is
[SwanSong SDK 0.5.0](https://github.com/RegionallyFamous/swansong-sdk/releases/tag/v0.5.0).
It already provides deterministic scene flow, animation, camera, collision,
grids, pools, pathfinding, state hashes, scenario compilation, exhaustive play,
semantic outcomes, native audio evidence, asset provenance, migration, and
release budgets.

The local SDK branch reviewed at commit
`9048ad7d5efde8b5a980126e716502020fd0a91c` adds deterministic tap, double-tap,
hold, and chord gestures plus timing grades, score chains, stable records, and
fixed-point motion. Those additions are not mislabeled as part of the public
0.5.0 tag. They make several optional story-native experiments practical:

- a timed social interruption whose success changes the next line, not whether
  the story can continue;
- a simultaneous dual-pad action expressing cooperation between two
  characters;
- a short hold-and-release action that makes hesitation physically legible;
- a recurring motif challenge whose score or record becomes diegetic history;
- gentle motion or bounce used for one expressive object rather than a generic
  arcade detour; and
- a replayable epilogue vignette whose state hash, outcome, record, and save
  behavior can be proven deterministically.

Every experiment should keep the story state portable, bound the interaction,
drain input at scene boundaries, give immediate visual and audio feedback,
allow failure to progress, and include the complete title-to-ending route in
SwanSong testing.

## Evidence boundary

Research on memory, transportation, suspense, and audiovisual music can guide
better questions. It cannot produce a universal story score. Genre, culture,
reader history, style, ambiguity, rereading, and deliberate anti-structure all
matter. Consequently:

- the framework reports structure but does not prescribe a single structure;
- reader evidence remains attributable and preserves disagreement;
- automated checks can block stale, missing, broken, or falsely delivered
  evidence, but never issue human approval;
- production art starts in ImageGen and still receives visual review; and
- generated music remains an audition until a person hears it in context.

## Primary and authoritative sources

- Hongmi Lee and Janice Chen,
  [Predicting memory from the network structure of naturalistic events](https://pmc.ncbi.nlm.nih.gov/articles/PMC9307577/),
  *Nature Communications* (2022).
- James Antony et al.,
  [Causal and Chronological Relationships Predict Memory Organization for Nonlinear Narratives](https://pubmed.ncbi.nlm.nih.gov/38991132/),
  *Journal of Cognitive Neuroscience* (2024).
- [Characters matter: How narratives shape affective responses to risk communication](https://pmc.ncbi.nlm.nih.gov/articles/PMC6901229/),
  *PLOS ONE* (2019).
- [The Power of the Picture: How Narrative Film Captures Attention and Disrupts Goal Pursuit](https://pmc.ncbi.nlm.nih.gov/articles/PMC4675523/),
  *PLOS ONE* (2015).
- [Toward a general psychological model of tension and suspense](https://pmc.ncbi.nlm.nih.gov/articles/PMC4324075/),
  *Frontiers in Psychology* (2015).
- [Confronting a Paradox: A New Perspective of the Impact of Uncertainty in Suspense](https://pmc.ncbi.nlm.nih.gov/articles/PMC6092602/),
  *Frontiers in Psychology* (2018).
- [How Soundtracks Shape What We See](https://pmc.ncbi.nlm.nih.gov/articles/PMC7575867/),
  *Frontiers in Psychology* (2020).
- [Unforgettable film music: The role of emotion in episodic long-term memory for music](https://pmc.ncbi.nlm.nih.gov/articles/PMC2430709/),
  *BMC Neuroscience* (2008).
- [SwanSong Desktop 0.7.2 release](https://github.com/RegionallyFamous/SwanSong-Desktop/releases/tag/v0.7.2).
- [SwanSong SDK 0.5.0 release](https://github.com/RegionallyFamous/swansong-sdk/releases/tag/v0.5.0).
