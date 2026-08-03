# Mobile Suit Gundam: The One Year Tour

An unofficial, noncommercial, full-spoiler WonderSwan Color museum tour through
the original *Mobile Suit Gundam* television story. Two tiny museum docents—an
RX-78-2 and a Zaku II—race a closing clock while explaining who acted, what
changed, and why the next event followed.

Four choices change emphasis and optional context, never canon:

- White Base or war-map lens for the Earth campaign;
- an optional White Base personnel plaque;
- an optional Zabi command plaque;
- people or power lens for the final space campaign.

All sixteen route combinations cover the complete chronology and end at A Baoa
Qu. Each route now contains 36–38 scene beats, about 2,500–2,700 words,
roughly 18–19 minutes of reading, and twelve distinct runtime backgrounds. The
canonical adaptation script, route graph, animation masks, Story Proof, and
diegetic SFX plan live in `assets/sources/game_spec.json`.

## Build and test

From the repository root:

```sh
python3 scripts/build_wscvn_game.py mobile-suit-gundam-summary
python3 scripts/check_wscvn_experience_polish.py \
  --contract games/mobile-suit-gundam-summary/assets/sources/experience-contract.json \
  --project games/mobile-suit-gundam-summary/projects/mobile-suit-gundam-summary.wscvn.json \
  --out games/mobile-suit-gundam-summary/reports/experience-polish-report.json
python3 scripts/playtest_wscvn_swansong.py mobile-suit-gundam-summary --route all
python3 scripts/check_wscvn_story_proof.py \
  --contract games/mobile-suit-gundam-summary/assets/sources/story-proof.json \
  --project games/mobile-suit-gundam-summary/projects/mobile-suit-gundam-summary.wscvn.json \
  --playthrough games/mobile-suit-gundam-summary/reports/swansong-playthrough-report.json \
  --out games/mobile-suit-gundam-summary/reports/story-proof-report.json \
  --html games/mobile-suit-gundam-summary/reports/story-ribbon.html
python3 scripts/refresh_wscvn_candidate_summary.py mobile-suit-gundam-summary
```

In SwanSong, click the display before playing. **X** is WonderSwan A
(confirm/advance), **Z** is B, arrow keys move through choices, and **Return**
is Start.

## Production rules

- Every production illustration is an ImageGen master. Fourteen museum
  environments and four character-pose families replace repeated-room staging.
  Local code only removes
  chroma, crops, resizes, quantizes, snaps RGB444 color, and derives tightly
  masked mechanical sensor frames.
- Every scene transition uses the runtime's complete 15-level fade with a
  black hold; there are no authored hard cuts.
- Seven long-form, low-density museum cues share one transformed motif and
  change only at story pivots. Eight object-specific effects punctuate relays,
  maps, glass, badges, and doors. Tracker channel 2 stays reserved for those
  one-shots so an effect cannot tear an essential score voice.
- Character bodies never change during dialogue. RX's two eye sensors and
  Zaku's mono-eye reserve locked green and pink RGB444 palette anchors,
  respectively, then close into aligned one-pixel shutter slits. The runtime
  never substitutes a broad talk face.
- The script borrows no series dialogue, screenshots, logos, lyrics, or music.
- This cartridge is for private/noncommercial study and play. Any
  public distribution is a separate rights decision.

Research, ImageGen prompts, the cue-by-cue audio redesign, agent roles, and the
human-readable story map are kept beside the game under `assets/sources/` and
in `docs/series-summary-visual-novels.md`.

`experience-contract.json` prevents the route length, background variety, and
ending completeness from silently regressing. It also keeps three genuinely
human approvals explicit: reader playtest, music listening, and physical
WonderSwan hardware. Candidate builds may preserve those lanes as pending;
release packaging refuses to treat them as automated passes.
