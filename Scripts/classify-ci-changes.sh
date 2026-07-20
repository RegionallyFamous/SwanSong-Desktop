#!/bin/bash
set -euo pipefail

release_chain=false
compatibility=false
translation=false
av=false

classify_path() {
  local path=$1

  case "$path" in
    .github/workflows/* | \
    Dependencies/* | \
    Packaging/* | \
    Package.swift | \
    Package.resolved | \
    Sources/SwanSongApp/HomebrewCatalogProductionTrust.swift | \
    Sources/SwanSongApp/SwanSongUpdater.swift | \
    Scripts/ares-source-state.sh | \
    Scripts/build-app.sh | \
    Scripts/check-app-*.sh | \
    Scripts/check-engine-reproducibility.sh | \
    Scripts/check-release-*.sh | \
    Scripts/check-sparkle-*.sh | \
    Scripts/classify-ci-changes.sh | \
    Scripts/generate-app-icons.sh | \
    Scripts/materialize-*.sh | \
    Scripts/notarize-app.sh | \
    Scripts/package-release.sh | \
    Scripts/release-app.sh | \
    Scripts/prepare-ares.sh | \
    Scripts/selftest-app-*.sh | \
    Scripts/selftest-ares-*.sh | \
    Scripts/selftest-ci-*.sh | \
    Scripts/selftest-package-*.sh | \
    Scripts/selftest-release-*.sh | \
    Scripts/selftest-sparkle-*.sh | \
    Scripts/selftest-swansong-sdk-payload.sh | \
    Scripts/swansong-sdk-payload.py | \
    Scripts/validate-source-archive.py | \
    Scripts/verify-app-*.sh | \
    Scripts/verify-release-*.sh)
      release_chain=true
      ;;
  esac

  case "$path" in
    Engine/* | \
    Sources/CSwanEngine/* | \
    Sources/SwanSongProbe/* | \
    Sources/SwanSongKit/ControllerProfile.swift | \
    Sources/SwanSongKit/DisplayProfile.swift | \
    Sources/SwanSongKit/EngineSession.swift | \
    Sources/SwanSongKit/FrameActivityMonitor.swift | \
    Sources/SwanSongKit/OpenIPL.swift | \
    Scripts/ares-source-state.sh | \
    Scripts/build-engine.sh | \
    Scripts/check-compatibility-matrix.sh | \
    Scripts/check-input-frame-bridge.sh | \
    Scripts/check-live-engine.sh | \
    Scripts/check-engine-reproducibility.sh | \
    Scripts/prepare-ares.sh | \
    Scripts/selftest-ares-*.sh | \
    testroms/*)
      compatibility=true
      ;;
  esac

  case "$path" in
    Engine/* | \
    Sources/CSwanEngine/* | \
    Sources/SwanSongApp/LocalMCPBridge.swift | \
    Sources/SwanSongApp/Translation*.swift | \
    Sources/SwanSongDifferential/* | \
    Sources/SwanSongRouteRunner/* | \
    Sources/SwanSongTextIntakeChecks/* | \
    Sources/SwanSongKit/EngineSession.swift | \
    Sources/SwanSongKit/LocalMCPAccess.swift | \
    Sources/SwanSongKit/SwanSongPlaytester.swift | \
    Sources/SwanSongKit/Translation*.swift | \
    Tools/SwanSongMCP/* | \
    Tools/SwanSongPlaytestMCP/* | \
    Scripts/check-mcp-server.sh | \
    Scripts/check-playtest-cli.sh | \
    Scripts/check-playtest-mcp-server.sh | \
    Scripts/check-translation-*.sh | \
    Scripts/run-swansong-mcp.sh | \
    Scripts/run-swansong-playtest-mcp.sh | \
    Tests/TranslationLabFixture/*)
      translation=true
      ;;
  esac

  case "$path" in
    Engine/* | \
    Sources/CSwanEngine/* | \
    Sources/SwanSongSoak/* | \
    Sources/SwanSongApp/AudioOutput.swift | \
    Sources/SwanSongKit/EngineSession.swift | \
    Sources/SwanSongKit/FrameAdvanceGate.swift | \
    Sources/SwanSongKit/FramePacing.swift | \
    Scripts/check-av-soak.sh)
      av=true
      ;;
  esac
}

if [[ $# -eq 1 && $1 == "--paths-from-stdin" ]]; then
  while IFS= read -r path; do
    classify_path "$path"
  done
elif [[ $# -eq 2 ]]; then
  base_revision=$1
  head_revision=$2
  while IFS= read -r -d '' path; do
    classify_path "$path"
  done < <(git diff --name-only -z "$base_revision" "$head_revision")
else
  echo "usage: $0 <base-revision> <head-revision>" >&2
  echo "       $0 --paths-from-stdin" >&2
  exit 64
fi

preflight=false
if [[ "$release_chain" == true \
  || "$compatibility" == true \
  || "$translation" == true \
  || "$av" == true ]]; then
  preflight=true
fi

printf 'preflight=%s\n' "$preflight"
printf 'release_chain=%s\n' "$release_chain"
printf 'compatibility=%s\n' "$compatibility"
printf 'translation=%s\n' "$translation"
printf 'av=%s\n' "$av"
