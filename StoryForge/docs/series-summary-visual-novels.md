# Series-summary visual novels

This lane adapts a complete television series into a concise visual novel while
preserving chronology, causality, tone, and uncertainty. The first reference is
`games/mobile-suit-gundam-summary`.

## Workflow

1. The **Canon Cartographer** declares one continuity and produces an
   authoritative episode ledger. Every episode receives an explicit
   KEEP/MERGE/NOD decision.
2. The **Causal Summary Storysmith** chooses a repeatable framing situation,
   then writes a complete causal route before adding lens choices. Choices may
   change attention and interpretation, but not canon outcomes.
3. The **Showrunner** creates all production masters with ImageGen, derives
   runtime-safe sprites from locked neutrals, gives every music cue a dramatic
   job, reserves a PCM lane when needed, and compiles the cartridge.
4. A game-specific `experience-contract.json` measures every route's words,
   reading time, scene beats, background variety, maximum repeated-room run,
   terminal-page length, and ending-background distinction. It preserves
   reader, music-listening, and physical-hardware approvals as explicit human
   lanes instead of silently converting automation into taste claims.
5. The exact ROM runs through every graph-derived choice combination in
   SwanSong. Story Proof binds key turns to observed nodes, fades, input,
   native audio when declared, and ending captures. A scored project also runs
   a long soak that rejects accidental silence, clipping, and stuck PCM state.
6. Research, prompt records, source hashes, readable story map, agent drafts,
   build instructions, and honest approval status stay in the repository.

## Quality contract

- One declared edition; no continuity soup.
- At least 25 experienced scene beats and roughly 1,800–3,000 words per ending
  route, with a game-specific target expressed in minutes. The current museum
  reference tightens that floor to 36 beats, 2,500 words, and about 18 minutes
  on every route.
- A causal sentence for every major transition: because X changed, Y can or
  must happen next.
- A framing cast with its own goal, pressure, comic engine, and final payoff.
- At least two canon-safe interpretive choices for a four-route test matrix.
- ImageGen-only production art, preserved high-resolution masters, native-size
  review, and hash-bound provenance. Major locations, memorial beats, optional
  guides, and distinct endings need their own compositions; a route must not
  pass by recoloring one repeated room.
- Audio must serve reading and place. Music is optional, but the default scored
  pattern is a shared motif across long, low-density cues with internal A/B
  contrast and changes only at story pivots. Intentional silence can punctuate
  a scene. Short exhibit effects belong on a reserved PCM lane so they do not
  tear the score.
- When the novel and VN share a score, set
  `soundtrack_bible.adaptation_project` to the repository-relative WSC VN
  project and map cues with `adaptation_track_id`. The music workbench imports
  the exact tempo, 192-step patterns, held notes, muted PCM lane, and source
  hash instead of inventing a generic 32-step replacement.
- Visible story text stays inside the fiction. Rights notices, adaptation
  language, episode-count promises, and production-method disclaimers belong in
  package documentation, never in docent dialogue or choice labels.
- Full fades and black holds; no hard scene-swap blink.
- Fade proof measures visible recovery above the compiled black basin, not
  similarity to the outgoing scene's brightness. A deliberately dark memorial
  must still show a multi-level fade, a real black hold, no swap flash, and a
  visible recovery.
- Locked mechanical faces: if a localized talk mechanism is not convincing,
  use blink-only staging. A blink may alter only authored eye/sensor pixels,
  with the body and socket geometry byte-locked to neutral. The sensor must
  compress into a distinct 3-8 pixel, one-pixel-high shutter slit; making it
  disappear is a power-off effect, not a blink. At the current 75 Hz runtime,
  use an eight-frame closed dwell and roughly 210 open frames between blinks.
  Reserve an RGB444 palette anchor for tiny critical sensors before
  quantization; otherwise a large prop or background color can silently absorb
  an eye. Alternate poses require their own authored masks and exact
  runtime-ready audition evidence.
- Exhaustive SwanSong progression, route time, native audio, accepted input,
  exact save/load replay, settings persistence, fade recovery, distinct ending
  captures, and a project-declared long audio soak that matches the score or
  SFX architecture.
- No claim that automation proves literary quality or grants franchise rights.
- Candidate reports may list human approvals as pending without failing their
  automated scope. Release packaging must fail while any approval marked
  `required_for_release` remains pending.

## Reference commands

```sh
python3 scripts/build_wscvn_game.py mobile-suit-gundam-summary
python3 scripts/check_wscvn_experience_polish.py \
  --contract games/mobile-suit-gundam-summary/assets/sources/experience-contract.json \
  --project games/mobile-suit-gundam-summary/projects/mobile-suit-gundam-summary.wscvn.json \
  --out games/mobile-suit-gundam-summary/reports/experience-polish-report.json
python3 scripts/playtest_wscvn_swansong.py mobile-suit-gundam-summary --route all
python3 scripts/refresh_wscvn_candidate_summary.py mobile-suit-gundam-summary
python3 scripts/ship_wscvn_game.py mobile-suit-gundam-summary
```

Shipping remains a separate decision from building and testing. A private fan
summary can be technically complete while public distribution still requires a
deliberate rights review.
