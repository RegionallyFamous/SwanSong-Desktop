# WonderSwan Runtime Audio Timing

The upstream VN runtime originally advanced tracker steps and PCM lifetimes as
if VBlank ran at 60 Hz. A default WonderSwan frame is 40,704 clocks at 3.072
MHz, approximately 75.472 Hz. That made music about 25.8 percent too fast and
stopped one-shot effects early.

Apply the Story Forge patch from the upstream repository root:

```bash
git apply --unidiff-zero \
  /path/to/SwanSong-Desktop/StoryForge/runtime-patches/visual-novel-creator-story-forge-runtime.patch
```

The patch uses an exact reduced accumulator for 16th-note tracker steps,
counts 4 kHz PCM at 53 samples per default frame, and suppresses PCM dialogue
ticks while music or authored scene audio is active. Channel 2 is the hardware
sample channel, so repeated PCM text ticks otherwise remove the score's second
voice during typewriter animation.

Hardware references:

- https://ws.nesdev.org/wiki/Timing
- https://wonderful.asie.pl/doc/general/target-wonderswan/

After applying the patch, rebuild and record at least two loops from the ROM.
`check_wscvn_audio_proof.py` verifies the measured repeat period as well as
duration, level, clipping, silence, project hash, and ROM hash.
