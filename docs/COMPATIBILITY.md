# Compatibility and accuracy claims

SwanSong uses the WonderSwan-family core from the exact ares revision recorded
in `Dependencies/ares.lock.json`.

**“Reached Video” means the emulator produced a meaningful game raster. It is
not a full-game compatibility verdict or an original-hardware accuracy claim.**
Compatibility remains specific to a title, region, revision, system startup
file, and test route.

SwanSong keeps three different signals separate:

- **Launch Readiness** checks whether the managed game, required startup file,
  and execution engine are available.
- **Compatibility Evidence** records an observed video milestone separately
  from the user's own Works or Issues verdict.
- **ROM Integrity** checks the managed copy and available footer evidence; it
  does not establish legal provenance or complete correctness.

The checked-in compatibility matrix uses only open or clean-room fixtures. It
exercises engine paths and reports what was observed without generalizing those
results to commercial software.

Public compatibility reports must name the tested version and revision, state
the scope of the route, avoid private hashes or artifacts, and distinguish
emulator agreement from original-hardware measurement.
