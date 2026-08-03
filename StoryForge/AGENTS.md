## Project Playbook

- Treat `skills/forge-light-novels` as the narrative source framework for new
  stories and major rewrites. Create a stable `novel.json`, pass its `concept`
  and `outline` gates before production art, and pass its `revision` gate before
  calling a WonderSwan adaptation finished. A standalone prose release also
  requires the `release` gate and explicit human approval bound to the exact
  manuscript and approved-art hashes. Schema v3 also requires genre pleasures,
  a series/standalone contract, scene delivery, typed continuity, chemistry,
  signature moments, reader synthesis, a rights lane, optional soundtrack
  motifs, an ImageGen illustration bible with full-set review, publication
  configuration, and a current project lockfile.
- Never bulk-expand a short story by rotating stock observations, shuffled
  callbacks, generic quiet beats, or paraphrased filler. Every planned scene
  needs a goal, pressure, turn, decision, consequence, and meaningfully changed
  exit state connected to an earlier scene through `because_of` causality.
  Draft validation must reject duplicate sentences, repeated long phrases,
  duplicated paragraphs, unfinished scene markers, and known stock filler.
- Keep character voice contracts, setup/payoff IDs, motif evolution, delight
  and rhythm maps, genre/series continuity, revision evidence, unprimed general
  and target-reader findings, publication proofs, and remaining risks in the
  novel manifest. Run voice, prose, momentum, scene-delivery, continuity,
  reader-synthesis, rights, and applicable soundtrack reports; bind report
  bytes and editorial responses to the exact manuscript.
  Numeric checks expose omissions; they do not prove artistry. Never invent a
  human reader, reviewer, or release approval.
- Use the Story Room as proposal-only specialists. The premise scout, architect,
  character editor, continuity editor, prose editor, art director, music
  director, and release editor must cite project evidence and may not silently
  mutate prose or canon. The human lead writer selects and merges their work.
  Preserve revision snapshots and reader disagreement instead of overwriting or
  averaging them.
- For a full-series summary visual novel, use the three proposal-only Agent
  Builder roles documented in `agents/series-summary-story-forge.md`: Canon
  Cartographer, Causal Summary Storysmith, and Franchise Summary Showrunner.
  Lock one declared continuity; record a KEEP/MERGE/NOD decision for every
  episode; make choices alter emphasis rather than canon; and preserve source,
  omission, contradiction, terminology, and rights ledgers. Keep player-facing
  titles, dialogue, prompts, and choices entirely diegetic: rights notices,
  episode totals, adaptation language, and production disclaimers belong in
  repository documentation. Do not publish an Agent Builder draft without
  explicit human action.
- A series-summary route must still meet the finished-story pacing floor. It
  needs its own framing cast, pressure, comic engine, setups/payoffs, and final
  image rather than functioning as a narrated encyclopedia. Research claims,
  the readable story map, exact ImageGen prompts, source hashes, audio design
  plan, route matrix, SwanSong evidence, and honest human-approval status all
  belong in the repository.
- For polished or expanded games, declare
  `assets/sources/experience-contract.json` using
  `wscvn-experience-polish-v1`. Set the per-route word/minute/scene floor,
  distinct-background floor, repeated-background ceiling, terminal-page floor,
  and distinct-ending requirement from the actual design. The normal build
  runs this contract in candidate mode. Keep real reader, subjective
  music-listening, and physical-hardware lanes explicitly pending until named
  evidence exists; release packaging must refuse pending approvals marked
  `required_for_release`.
- Keep `novel.json` and the manuscript as narrative source of truth. Workbench
  maps, context, research, art prompts, music auditions, and adaptation outputs
  use the fixed `scripts/forge.py` JSON contracts shared with SwanSong Desktop.
- Generate and review `forge story-pulse` during outline/revision work so causal
  load, open reader questions, motif appearances, and accidental flat rhythm
  runs stay visible. These diagnostics are never a mandatory emotional curve or
  a quality score.
- Every Story Forge WonderSwan adaptation must keep its generated per-scene
  Story Proof contract. Production fills in route variants, reachable next
  states, approved ImageGen presentation, intentional audio, fade/audio/input
  requirements, and ending captures. When a game declares
  `assets/sources/story-proof.json`, shipping must run
  `scripts/check_wscvn_story_proof.py` after the exhaustive SwanSong playthrough
  and before packaging; the hash-bound report and Story Ribbon are release
  evidence. A passing proof establishes delivery only, never literary quality.
- Live Reader Lab moments require a real reader identity, verbatim local note,
  stable scene ID, and current manuscript hash. Never invent reactions or
  average `laughed`, `moved`, `confused`, `paused`, `bored`, and `wanted-more`
  into one score.
  Never introduce a second desktop-only story engine or arbitrary command lane.
- Use ImageGen for every new or replacement production illustration, including
  characters, backgrounds, title art, cinematic inserts, covers, and cartridge
  labels. Do not substitute scripted, procedural, vector-primitive, or
  code-painted scene art. Scripts may only post-process an ImageGen or
  user-supplied master: chroma-key, crop, resize, quantize, snap to RGB444,
  assemble layouts, add exact lettering/UI, derive localized talk/blink frames,
  and produce proof sheets. If ImageGen is unavailable, stop the art pass and
  report the blocker instead of shipping fallback programmer art.
- Preserve a high-resolution ImageGen master with a versioned filename and
  record its provenance before accepting any derived runtime asset. Existing
  user-supplied art may be preserved and reused, but newly created pictorial
  artwork must still follow the ImageGen-first rule.
- For prose releases, build both EPUB and PDF with
  `scripts/build_novel_release.py`, inspect the rendered all-page PDF contact sheet, and
  generate the cross-volume catalog with `scripts/build_series_bible.py` when
  the project is part of a series.
- Generate one master per pose and derive animation locally. Human blinks use
  compact one-pixel eyelids inside actual eye apertures with explicit skin
  sample points; mechanical blinks use per-character authored camera/sensor
  masks with explicit sensor/socket samples plus a 3-8 pixel, one-pixel-high
  shutter segment in a distinct existing palette color. A sensor that merely
  vanishes into its socket is a power-off frame, not a blink. Mechanical talk frames use the
  same locked neutral and tight authored sensor masks, but pulse only the
  connected sensor component toward an existing sampled palette color. Never
  ImageGen a separate blink face, invert fixed face rectangles, draw broad
  face/visor bars, move glasses, or change pixels outside the approved
  eye/sensor band. Visually approve the exact runtime-ready neutral/talk/blink
  PNG strip and bind its hashes before integration.
- If mechanical talk motion is not convincingly localized, stage the character
  as blink-only: neutral is the body-locked base, frame two is the aligned
  blink, and no talk frame may be substituted while text prints. Release QA
  must reject `talk-blink` when the project declares blink-only staging.
- Background music is optional, but never choose between a tiny foreground loop
  and undifferentiated silence. For reading-heavy museum or archive framing,
  prefer long, low-density cues with a shared motif, internal A/B contrast, and
  changes only at narrative pivots. Use intentional silence as punctuation.
  When one-shot PCM effects are present, reserve tracker channel 2 unless a
  proven arbitration plan protects every important voice. Scored projects must
  pass a long continuous-music SwanSong soak with no accidental silent windows,
  non-finite samples, material clipping, or stuck PCM state.
  Preview and emulator-proof tools must derive loop duration from each track's
  current `lengthSteps`; never retain a hard-coded 32-step timing assumption
  after adopting long-form cues.
- Treat fades as compiled-raster behavior. The runtime must traverse all 15
  RGB444 levels, hide display layers during scene VRAM/palette work, restore
  the known `SCR1|SCR2` layer state without trusting display-register readback,
  restore black before fade-in, and hold black for at least two frames.
  SwanSong proof must reject a bright scene-swap spike, a black-screen fade-in,
  or a short hard cut.
- Do not release ten-node story prototypes as finished games. Each complete
  ending route should have at least 25 scene beats and roughly 1,800-3,000
  words (about 15-25 minutes), with meaningful escalation, callbacks, choices,
  and ending payoff unless a documented pacing plan justifies an exception.
  The word floor is subordinate to the novel framework's anti-filler and causal
  scene gates.
- Treat text as a 26-column by 4-line runtime surface, never a 32-column tile
  map. Every game builder must losslessly repaginate at word boundaries with
  `scripts/wscvn_text_layout.py`; readiness must prove no page or choice is
  clipped and no dialogue word is dropped or joined across `{pause}`.
- Treat graphics quality as the primary product goal. Do not expand build
  tooling while the source art, sprites, backgrounds, font, or real 224x144
  previews are still weak.
- Preserve generated image assets and source sheets. Never add cleanup logic
  that deletes them; superseded art remains comparison and fallback material.
- Keep the canonical Codex skill in `skills/build-wonderswan-vn` and the
  installed copy in `~/.codex/skills/build-wonderswan-vn` synchronized.
- Keep `runtime-local/`, ROMs, release archives, and stale runtime snapshots out
  of Git. Authored projects, approved source art, runtime-ready art, and current
  proof reports belong in Git.
- Use SwanSong, not Mesen, as the primary compiled progression gate. Preflight
  and record the installed engine ABI before route evidence. Treat
  ABI/session startup as a harness failure and overwrite stale green reports
  with explicit failure evidence. Run every graph-derived route, validate
  visible per-route progress and retain each route's wall time so large route
  matrices cannot look like an unexplained hang,
  accepted input, native audio, exact save-state
  replay, in-game save/load across an engine restart, persisted player options,
  fade-in recovery, and route captures. Before a complete rerun, move only
  exact old `route-N-{ending,audio,stall}` captures into the timestamped
  `reports/runtime-stale/` quarantine; never delete route evidence in place.
  Doctor timeouts must terminate the entire command process group, including
  emulator grandchildren, and remain covered by
  `selftest_story_forge_doctor_timeout.py`.
  Full-game doctor deadlines must scale from the exhaustively enumerated route
  count. A fixed whole-game deadline can turn a healthy long route matrix into
  a false progression failure; keep a bounded minimum and maximum and cover a
  27-route project in `selftest_story_forge_doctor_timeout.py`.
  Map mailbox node indices through the converter's stable compiled node order,
  never raw JSON list order. Distinct final scene nodes
  must end on distinct terminal payoff pages and produce distinct captures;
  readiness must reject matching terminal text/visual signatures before build.
  Mesen/Mednafen remain independent visual/boot/audio proof.
- Use `ship_wscvn_game.py` for releases; its required order is build,
  exhaustive SwanSong playthrough, package, then verification. Never package a
  partial `--route` report.
- When a candidate is current but required human approvals block packaging,
  run `refresh_wscvn_candidate_summary.py <slug>` after the exhaustive
  playthrough. Keep the prior zip labeled as a previous release and bind the
  current ROM, route count, art counts, Story Proof, and pending approvals in
  the candidate summary and `CURRENT_RELEASES.md`.
- Keep the runtime's Auto, Skip Read, Text Speed, music/SFX volume, continue
  indicator, and schema-5 read/settings persistence functional. Treat a schema
  bump as an SRAM migration that invalidates older saves.

## Done When

- `python3 scripts/check_forge_light_novels_skill.py
  --require-installed-match` and
  `python3 scripts/selftest_light_novel_framework.py` pass after novel
  framework changes.
- `python3 scripts/selftest_forge_workbench.py` passes after Story Room,
  manuscript editor, reader/research, art/music room, or adaptation changes.
- `python3 scripts/check_build_wonderswan_vn_skill.py --require-installed-match`
  passes after skill changes.
- `python3 scripts/selftest_wscvn_experience_polish.py` passes after experience
  contract, route pacing, ending, or human-approval-lane changes.
- `python3 scripts/selftest_wscvn_transition_continuity.py` passes after fade
  runtime or SwanSong fade-proof changes. Its fixtures must cover a genuinely
  black screen, an intentionally dark incoming scene, and back-to-back fades.
- `python3 scripts/selftest_wscvn_audio_proof_timing.py` passes after tracker
  timing or audio-proof changes so long-form cues can never regress to a
  hard-coded 32-step assumption.
- `python3 scripts/doctor_story_forge.py --build-games` passes after workflow,
  game, art, or release changes.
- `python3 scripts/status_story_forge.py --check-index CURRENT_RELEASES.md
  --no-write` passes after release evidence changes.
- `git diff --check` passes.
