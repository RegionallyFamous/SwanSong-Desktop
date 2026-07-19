#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
UNIVERSAL=${SWAN_UNIVERSAL:-0}
case "$UNIVERSAL" in
  0)
    DEFAULT_ENGINE_BUILD_DIR="$MACOS_DIR/.engine/build-app"
    ;;
  1)
    DEFAULT_ENGINE_BUILD_DIR="$MACOS_DIR/.engine/build-app-universal"
    ;;
  *)
    echo "unknown SWAN_UNIVERSAL '$UNIVERSAL' (use 0 or 1)" >&2
    exit 2
    ;;
esac
BUILD_DIR=${ARES_BUILD_DIR:-"$DEFAULT_ENGINE_BUILD_DIR"}
CONFIGURATION=${CONFIGURATION:-release}
OUTPUT_DIR=${SWAN_APP_OUTPUT_DIR:-"$MACOS_DIR/.build/app"}
APP_DIR="$OUTPUT_DIR/SwanSong.app"
UNIVERSAL_SWIFT_DIR=${SWAN_UNIVERSAL_SWIFT_DIR:-"$MACOS_DIR/.build/swan-universal"}
SIGNING_MODE=${SWAN_SIGNING_MODE:-adhoc}
SIGNING_IDENTITY=${SWAN_CODE_SIGN_IDENTITY:-}
SDK_REPOSITORY=${SWAN_SDK_SOURCE_REPOSITORY:-"$MACOS_DIR/../swansong-sdk"}
SDK_PAYLOAD_SOURCE=${SWAN_SDK_PAYLOAD_SOURCE:-}
SOURCE_COMMIT=$(git -C "$MACOS_DIR" rev-parse --verify HEAD)
printf '%s\n' "$SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$' || {
  echo "could not determine a 40-character Git source commit" >&2
  exit 1
}
SOURCE_TREE_DIRTY=false
if [ -n "$(git -C "$MACOS_DIR" status --porcelain --untracked-files=all)" ]; then
  SOURCE_TREE_DIRTY=true
fi

python3 "$SCRIPT_DIR/check-sparkle-dependency-lock.py" \
  --repository "$MACOS_DIR" >/dev/null
if [ "${SWAN_RELEASE_BUILD:-0}" = "1" ]; then
  python3 "$SCRIPT_DIR/check-yokoi-hardware-payload.py" --release \
    "$MACOS_DIR/Packaging/YokoiHardware" >/dev/null
else
  python3 "$SCRIPT_DIR/check-yokoi-hardware-payload.py" \
    "$MACOS_DIR/Packaging/YokoiHardware" >/dev/null
fi
if [ "${SWAN_RELEASE_BUILD:-0}" = "1" ] \
  && [ -n "${SWAN_SPARKLE_FRAMEWORK_SOURCE:-}" ]; then
  echo "release builds cannot override the pinned SwiftPM Sparkle artifact" >&2
  exit 1
fi

find_signing_identity() {
  prefix=$1
  security find-identity -v -p codesigning 2>/dev/null | awk -v prefix="$prefix" '
    index($0, "\"" prefix) {
      sub(/^[^\"]*\"/, "")
      sub(/\"[^\"]*$/, "")
      print
      exit
    }
  '
}

signing_identity_matches() {
  requested=$1
  prefix=$2
  security find-identity -v -p codesigning 2>/dev/null | awk \
    -v requested="$requested" -v prefix="$prefix" '
    index($0, "\"") {
      hash = $2
      name = $0
      sub(/^[^\"]*\"/, "", name)
      sub(/\"[^\"]*$/, "", name)
      if (index(name, prefix) == 1 \
          && (name == requested || tolower(hash) == tolower(requested))) {
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  '
}

case "$SIGNING_MODE" in
  adhoc)
    SIGNING_IDENTITY=-
    ;;
  auto)
    if [ -n "$SIGNING_IDENTITY" ]; then
      if ! signing_identity_matches "$SIGNING_IDENTITY" "Developer ID Application:" \
        && ! signing_identity_matches "$SIGNING_IDENTITY" "Apple Development:"; then
        echo "the requested signing identity is not a valid installed Developer ID Application or Apple Development identity" >&2
        exit 1
      fi
    else
      SIGNING_IDENTITY=$(find_signing_identity "Developer ID Application:")
      if [ -z "$SIGNING_IDENTITY" ]; then
        SIGNING_IDENTITY=$(find_signing_identity "Apple Development:")
      fi
      if [ -z "$SIGNING_IDENTITY" ]; then
        SIGNING_IDENTITY=-
      fi
    fi
    ;;
  developer-id)
    if [ -z "$SIGNING_IDENTITY" ]; then
      SIGNING_IDENTITY=$(find_signing_identity "Developer ID Application:")
    fi
    if [ -z "$SIGNING_IDENTITY" ]; then
      echo "no Developer ID Application signing identity is installed" >&2
      exit 1
    fi
    if ! signing_identity_matches "$SIGNING_IDENTITY" "Developer ID Application:"; then
      echo "the requested Developer ID Application identity is not valid and installed" >&2
      exit 1
    fi
    ;;
  development)
    if [ -z "$SIGNING_IDENTITY" ]; then
      SIGNING_IDENTITY=$(find_signing_identity "Apple Development:")
    fi
    if [ -z "$SIGNING_IDENTITY" ]; then
      echo "no Apple Development signing identity is installed" >&2
      exit 1
    fi
    if ! signing_identity_matches "$SIGNING_IDENTITY" "Apple Development:"; then
      echo "the requested Apple Development identity is not valid and installed" >&2
      exit 1
    fi
    ;;
  *)
    echo "unknown SWAN_SIGNING_MODE '$SIGNING_MODE' (use adhoc, auto, developer-id, or development)" >&2
    exit 2
    ;;
esac

sign_code() {
  path=$1
  if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --sign - "$path"
  else
    codesign --force --timestamp --options runtime \
      --sign "$SIGNING_IDENTITY" "$path"
  fi
}

sign_sparkle_code() {
  path=$1
  preserve_entitlements=${2:-0}
  preserve_flags=
  if [ "$preserve_entitlements" = "1" ]; then
    preserve_flags=--preserve-metadata=entitlements
  fi
  # Follow Sparkle's manual distribution-signing order and preserve metadata
  # only for Downloader.xpc. In particular, retaining the artifact's ad-hoc
  # Autoupdate identifier is not part of Sparkle's supported signing recipe.
  if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --options runtime \
      $preserve_flags \
      --sign - "$path"
  else
    codesign --force --timestamp --options runtime \
      $preserve_flags \
      --sign "$SIGNING_IDENTITY" "$path"
  fi
}

SWAN_UNIVERSAL="$UNIVERSAL" \
ARES_BUILD_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/build-engine.sh" >/dev/null

if [ "$UNIVERSAL" = "1" ]; then
  SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
  ARM_SCRATCH="$UNIVERSAL_SWIFT_DIR/arm64"
  INTEL_SCRATCH="$UNIVERSAL_SWIFT_DIR/x86_64"

  SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --product SwanSong \
    --configuration "$CONFIGURATION" \
    --scratch-path "$ARM_SCRATCH" \
    --triple arm64-apple-macosx14.0 \
    --sdk "$SDK_PATH"
  SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --product SwanSongRouteRunner \
    --configuration "$CONFIGURATION" \
    --scratch-path "$ARM_SCRATCH" \
    --triple arm64-apple-macosx14.0 \
    --sdk "$SDK_PATH"
  ARM_BIN_DIR=$(SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --product SwanSong \
    --configuration "$CONFIGURATION" \
    --scratch-path "$ARM_SCRATCH" \
    --triple arm64-apple-macosx14.0 \
    --sdk "$SDK_PATH" \
    --show-bin-path)

  SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --product SwanSong \
    --configuration "$CONFIGURATION" \
    --scratch-path "$INTEL_SCRATCH" \
    --triple x86_64-apple-macosx14.0 \
    --sdk "$SDK_PATH"
  SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --product SwanSongRouteRunner \
    --configuration "$CONFIGURATION" \
    --scratch-path "$INTEL_SCRATCH" \
    --triple x86_64-apple-macosx14.0 \
    --sdk "$SDK_PATH"
  INTEL_BIN_DIR=$(SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --product SwanSong \
    --configuration "$CONFIGURATION" \
    --scratch-path "$INTEL_SCRATCH" \
    --triple x86_64-apple-macosx14.0 \
    --sdk "$SDK_PATH" \
    --show-bin-path)
else
  SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --product SwanSong \
    --configuration "$CONFIGURATION"
  SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --product SwanSongRouteRunner \
    --configuration "$CONFIGURATION"
fi

if [ -n "${SWAN_SPARKLE_FRAMEWORK_SOURCE:-}" ]; then
  SPARKLE_FRAMEWORK_SOURCE=$SWAN_SPARKLE_FRAMEWORK_SOURCE
  SPARKLE_UPSTREAM_PACKAGE=
else
  if [ "$UNIVERSAL" = "1" ]; then
    SPARKLE_ARTIFACT_ROOT="$ARM_SCRATCH/artifacts"
    SPARKLE_CHECKOUT_ROOT="$ARM_SCRATCH/checkouts"
  else
    SPARKLE_ARTIFACT_ROOT="$MACOS_DIR/.build/artifacts"
    SPARKLE_CHECKOUT_ROOT="$MACOS_DIR/.build/checkouts"
  fi
  SPARKLE_FRAMEWORK_SOURCE=$(find "$SPARKLE_ARTIFACT_ROOT" \
    -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' \
    -type d -print -quit 2>/dev/null || true)
  SPARKLE_UPSTREAM_PACKAGE=$(find "$SPARKLE_CHECKOUT_ROOT" \
    -path '*/Sparkle/Package.swift' -type f -print -quit 2>/dev/null || true)
fi
if [ ! -d "$SPARKLE_FRAMEWORK_SOURCE" ] \
  || [ -L "$SPARKLE_FRAMEWORK_SOURCE" ]; then
  echo "the Sparkle SwiftPM artifact framework could not be located" >&2
  exit 1
fi
if [ -n "$SPARKLE_UPSTREAM_PACKAGE" ]; then
  python3 "$SCRIPT_DIR/check-sparkle-dependency-lock.py" \
    --repository "$MACOS_DIR" \
    --upstream-package "$SPARKLE_UPSTREAM_PACKAGE" >/dev/null
elif [ "${SWAN_RELEASE_BUILD:-0}" = "1" ]; then
  echo "release build could not verify Sparkle's upstream artifact checksum" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Helpers"
mkdir -p "$APP_DIR/Contents/Frameworks"
mkdir -p "$APP_DIR/Contents/Resources"

if [ "$UNIVERSAL" = "1" ]; then
  xcrun lipo -create \
    "$ARM_BIN_DIR/SwanSong" \
    "$INTEL_BIN_DIR/SwanSong" \
    -output "$APP_DIR/Contents/MacOS/SwanSong"
  xcrun lipo -create \
    "$ARM_BIN_DIR/SwanSongRouteRunner" \
    "$INTEL_BIN_DIR/SwanSongRouteRunner" \
    -output "$APP_DIR/Contents/Helpers/SwanSongRouteRunner"
else
  cp "$MACOS_DIR/.build/$CONFIGURATION/SwanSong" "$APP_DIR/Contents/MacOS/SwanSong"
  cp "$MACOS_DIR/.build/$CONFIGURATION/SwanSongRouteRunner" \
    "$APP_DIR/Contents/Helpers/SwanSongRouteRunner"
fi
cp "$BUILD_DIR/libSwanAresEngine.dylib" "$APP_DIR/Contents/Frameworks/libSwanAresEngine.dylib"
ditto "$SPARKLE_FRAMEWORK_SOURCE" \
  "$APP_DIR/Contents/Frameworks/Sparkle.framework"
cp "$MACOS_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$MACOS_DIR/Packaging/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$MACOS_DIR/Packaging/AppIcon.png" "$APP_DIR/Contents/Resources/AppIcon.png"
cp "$MACOS_DIR/Packaging/AppIconCompact.png" \
  "$APP_DIR/Contents/Resources/AppIconCompact.png"
cp "$MACOS_DIR/Packaging/MenuBarSwan.png" \
  "$APP_DIR/Contents/Resources/MenuBarSwan.png"
cp "$MACOS_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
cp "$MACOS_DIR/PRIVACY.md" "$APP_DIR/Contents/Resources/PRIVACY.md"
cp "$MACOS_DIR/SUPPORT.md" "$APP_DIR/Contents/Resources/SUPPORT.md"
cp "$MACOS_DIR/Dependencies/THIRD_PARTY_NOTICES.md" \
  "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$MACOS_DIR/Dependencies/SPARKLE_LICENSE" \
  "$APP_DIR/Contents/Resources/SPARKLE_LICENSE"
cp "$MACOS_DIR/Dependencies/ares.lock.json" \
  "$APP_DIR/Contents/Resources/ares.lock.json"
cp "$MACOS_DIR/Dependencies/sparkle.lock.json" \
  "$APP_DIR/Contents/Resources/sparkle.lock.json"
ditto "$MACOS_DIR/Packaging/YokoiHardware" \
  "$APP_DIR/Contents/Resources/YokoiHardware"
python3 "$SCRIPT_DIR/check-yokoi-hardware-payload.py" \
  "$APP_DIR/Contents/Resources/YokoiHardware" >/dev/null
if [ -n "$SDK_PAYLOAD_SOURCE" ]; then
  "$SCRIPT_DIR/check-swansong-sdk-payload.sh" "$SDK_PAYLOAD_SOURCE" >/dev/null
  ditto "$SDK_PAYLOAD_SOURCE" "$APP_DIR/Contents/Resources/SwanSongSDK"
else
  "$SCRIPT_DIR/materialize-swansong-sdk.sh" \
    "$SDK_REPOSITORY" "$APP_DIR/Contents/Resources/SwanSongSDK" >/dev/null
fi
"$SCRIPT_DIR/check-swansong-sdk-payload.sh" \
  "$APP_DIR/Contents/Resources/SwanSongSDK" >/dev/null

list_rpaths() {
  otool -l "$1" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
    in_rpath && $1 == "path" { print $2; in_rpath = 0 }
  '
}

for executable in \
  "$APP_DIR/Contents/MacOS/SwanSong" \
  "$APP_DIR/Contents/Helpers/SwanSongRouteRunner"; do
  if otool -l "$executable" | grep -Fq "path $BUILD_DIR"; then
    install_name_tool -delete_rpath "$BUILD_DIR" "$executable"
  fi

  # SwiftPM can add the selected Command Line Tools or full-Xcode runtime
  # directory while cross-compiling. macOS 14 supplies the Swift runtime;
  # retaining any absolute developer-machine path would make the release bundle
  # non-portable. `sort -u` is important because otool prints each universal2
  # slice separately.
  development_swift_rpaths=$(list_rpaths "$executable" \
    | grep -E '^/(Library/Developer/CommandLineTools|Applications/.*Xcode[^/]*)/.*swift' \
    | sort -u \
    || true)
  while IFS= read -r rpath; do
    if [ -n "$rpath" ]; then
      install_name_tool -delete_rpath "$rpath" "$executable"
    fi
  done <<EOF
$development_swift_rpaths
EOF

  install_name_tool -add_rpath "@executable_path/../Frameworks" "$executable"

  if list_rpaths "$executable" \
    | grep -Eq '^/(Library/Developer/CommandLineTools|Applications/.*Xcode[^/]*)/.*swift'; then
    echo "an absolute developer-toolchain Swift runtime rpath remains in $executable" >&2
    exit 1
  fi
done

# Bind the exact source snapshot into the signed app. Recheck immediately
# before signing so a commit change or working-tree mutation during the build
# cannot be recorded as a clean build.
FINAL_SOURCE_COMMIT=$(git -C "$MACOS_DIR" rev-parse --verify HEAD)
if [ "$FINAL_SOURCE_COMMIT" != "$SOURCE_COMMIT" ] \
  || [ -n "$(git -C "$MACOS_DIR" status --porcelain --untracked-files=all)" ]; then
  SOURCE_TREE_DIRTY=true
fi
/usr/libexec/PlistBuddy -c \
  "Add :SwanSongSourceCommit string $SOURCE_COMMIT" \
  "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
  "Add :SwanSongSourceTreeDirty bool $SOURCE_TREE_DIRTY" \
  "$APP_DIR/Contents/Info.plist"

if [ "$UNIVERSAL" = "1" ]; then
  "$SCRIPT_DIR/verify-app-architectures.sh" "$APP_DIR"
fi

SPARKLE_VERSION_ROOT="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B"
sign_sparkle_code "$SPARKLE_VERSION_ROOT/XPCServices/Installer.xpc"
sign_sparkle_code "$SPARKLE_VERSION_ROOT/XPCServices/Downloader.xpc" 1
sign_sparkle_code "$SPARKLE_VERSION_ROOT/Autoupdate"
sign_sparkle_code "$SPARKLE_VERSION_ROOT/Updater.app"
sign_sparkle_code "$APP_DIR/Contents/Frameworks/Sparkle.framework"
sign_code "$APP_DIR/Contents/Frameworks/libSwanAresEngine.dylib"
sign_code "$APP_DIR/Contents/Helpers/SwanSongRouteRunner"
sign_code "$APP_DIR"

codesign --verify --deep --strict "$APP_DIR"
if [ "$SIGNING_IDENTITY" = "-" ]; then
  echo "Built an ad-hoc-signed app bundle." >&2
else
  echo "Built a hardened-runtime app signed with: $SIGNING_IDENTITY" >&2
fi

echo "$APP_DIR"
