# Audio redesign: a quiet, adaptive museum score

## Decision

The cartridge uses seven restrained tracker cues plus eight short, diegetic
museum sounds. Music remains present during reading, but it changes only at
narrative pivots and leaves deliberate space between phrases. The score shares
one four-note D-F-A-G identity across comic duty, travel, strategy, grief,
discovery, and two distinct endings.

The cues use a 192-step grid: twelve bars and roughly 34–55 seconds before a
repeat. Channel 2 stays silent in every tracker arrangement because the
WonderSwan uses that hardware voice for PCM. Museum relays, maps, glass, badges,
and doors can therefore sound without cutting an essential melody or bass part.
Dialogue does not produce a per-character blip.

## What the research changed

The old choice between a bright short loop and total silence was false.
Successful narrative games give music a job, vary familiar material, and use
silence as punctuation:

- *The Great Ace Attorney* treats every cue as a functional part of the game:
  deduction, pursuit, place, and character identity each need a clear dramatic
  job. Source:
  [Capcom's music-creation interview](https://news.capcomusa.com/lets/browse/the-adventures-and-resolve-of-music-creation).
- *Life Is Strange* asks why music belongs in a scene, tests it against the
  scene, avoids overuse, and keeps one coherent musical vision across the whole
  game. Source:
  [Life Is Strange audio-design GDC slides](https://media.gdcvault.com/gdc2019/presentations/barbet-raoul-life-is-strange.pdf).
- *Return of the Obra Dinn* groups related story passages, gives each group a
  paired A/B treatment, and alternates versions so the same music does not
  immediately repeat. Source:
  [Lucas Pope's development log](https://dukope.com/devlogs/obra-dinn/tig-33/).
- *UNDERTALE* prioritizes emotional fit, atmosphere, and a memorable main
  theme. That supports a reusable motif instead of seven unrelated tracks.
  Source:
  [Nintendo's Toby Fox interview](https://www.nintendo.com/jp/topics/article/e3db9051-ab54-11e8-b123-063b7ac45a6d).
- Longer loops, contrasting sections, partial orchestration, and occasional
  silence reduce loop fatigue more effectively than simply removing music.
  Source:
  [Rethinking the Audio Loop in Games](https://www.gamedeveloper.com/audio/rethinking-the-audio-loop-in-games).
- *Shovel Knight* keeps chip music stylistically authentic while using modern
  production judgment, and explicitly accounts for the way sound effects can
  steal music channels on older hardware. Source:
  [Breaking the NES](https://www.yachtclubgames.com/blog/breaking-the-nes/).

The WonderSwan provides four 32-sample, 4-bit wavetable channels; channel 2 can
become a PCM voice, channel 3 supports sweep, and channel 4 supports noise.
That hardware shape is part of the arrangement, not an afterthought. Reference:
[WonderSwan sound](https://ws.nesdev.org/wiki/Sound).

## Cue plan

| Cue | Dramatic job | BPM | Loop |
| --- | --- | ---: | ---: |
| Last Tour, Lights Low | Welcome the player and establish the closing clock | 58 | 49.7 s |
| Arrows Across the Glass | Carry maps, pressure, and military causality | 84 | 34.3 s |
| Whoever Kept Moving | Put White Base's people ahead of machine spectacle | 72 | 40.0 s |
| The Next Door Opens | Mark discovery, thresholds, and widening perception | 64 | 45.0 s |
| Names Under the Victory Lamp | Make victories retain grief and specific names | 52 | 55.4 s |
| Carry Every Name Home | Resolve the people-focused ending with warmth | 58 | 49.7 s |
| What the Machines Could Not Decide | Resolve the power-focused ending without triumphalism | 68 | 42.4 s |

Each cue has an internal A/B arc rather than one endlessly repeated two-bar
sentence. `musicAction: "keep"` carries the current cue through ordinary page
turns. Sixteen authored pivot nodes may change it; the two endings receive
different final arrangements.

## Release contract

- Exactly seven cues, each 192 steps long, must be present and wired.
- The title must start `track_last_tour`; the ending lenses must resolve to
  `track_names_carried` and `track_power_reckoning`.
- Tracker channel 2 must remain silent and reserved for one-shot PCM effects.
- `uiSfxText` must remain empty; authored object effects must never loop.
- The project must declare a 180-second `continuous-music` SwanSong soak.
- No ten-second soak window may collapse into accidental silence.
- The full soak must contain no non-finite samples or material clipping.
- Every cue must render for two loops before the ROM build so the real seam can
  be inspected.
- Human listening remains required for melody, balance, emotional fit, and the
  character of a physical WonderSwan speaker. Automated checks prove wiring and
  transport health, not musical taste.

## Animation interaction

Audio and character motion share the same restraint rule. The runtime stages
neutral plus blink only. RX closes the two existing eye sensors in place; Zaku
closes the existing mono-eye in place. The body, socket geometry, and character
position remain locked. The legacy talk asset slot is a neutral duplicate and
is never staged.
