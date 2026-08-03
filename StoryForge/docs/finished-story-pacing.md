# Finished Story Pacing

A short VN can be compact without being a premise demo. Story Forge's current
finished-game floor is measured per complete ending route:

- at least 25 scene beats;
- at least 1,800 dialogue words;
- a planning target of 1,800-3,000 words, or roughly 15-25 minutes at 140 wpm.

`scripts/check_wscvn_game_readiness.py` enumerates the same flag-, choice-,
branch-, and investigation-aware routes used by SwanSong playtesting. Its
`route_pacing` evidence records scene beats, dialogue words, and estimated
minutes for each ending route.

Length must come from story movement: escalation, reversals, decisions,
callbacks, quiet reaction beats, visible consequences, and ending payoff. Do
not satisfy the floor with duplicated nodes, repeated sentences, or filler.
Keep each `{pause}` block within the 100-character runtime limit and review the
actual textbox proofs. The runtime surface is 26 columns by 4 lines, not the
32-column tile-map width. Every builder calls `normalize_project_text()` from
`scripts/wscvn_text_layout.py` after project assembly so long authored prose is
repaginated at word boundaries without deleting or joining dialogue. Run
`scripts/selftest_wscvn_text_layout.py` after changing that logic.

When a scene expander adds shared texture or cadence pages, keep each ending's
branch-specific payoff as the final page of its final scene. The readiness
guard compares terminal text plus visible scene state across distinct endings,
and exhaustive SwanSong testing compares their native captures. This prevents
longer scripts from accidentally making separate endings look identical.
