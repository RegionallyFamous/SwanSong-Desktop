#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
UNIVERSAL=${SWAN_UNIVERSAL:-0}
case "$UNIVERSAL" in
  0)
    DEFAULT_ENGINE_BUILD_DIR="$MACOS_DIR/.engine/build"
    ;;
  1)
    DEFAULT_ENGINE_BUILD_DIR="$MACOS_DIR/.engine/build-universal"
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
    --configuration "$CONFIGURATION"
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Frameworks"
mkdir -p "$APP_DIR/Contents/Resources"

if [ "$UNIVERSAL" = "1" ]; then
  xcrun lipo -create \
    "$ARM_BIN_DIR/SwanSong" \
    "$INTEL_BIN_DIR/SwanSong" \
    -output "$APP_DIR/Contents/MacOS/SwanSong"
else
  cp "$MACOS_DIR/.build/$CONFIGURATION/SwanSong" "$APP_DIR/Contents/MacOS/SwanSong"
fi
cp "$BUILD_DIR/libSwanAresEngine.dylib" "$APP_DIR/Contents/Frameworks/libSwanAresEngine.dylib"
cp "$MACOS_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$MACOS_DIR/Packaging/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$MACOS_DIR/Packaging/AppIcon.png" "$APP_DIR/Contents/Resources/AppIcon.png"
cp "$MACOS_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
cp "$MACOS_DIR/PRIVACY.md" "$APP_DIR/Contents/Resources/PRIVACY.md"
cp "$MACOS_DIR/SUPPORT.md" "$APP_DIR/Contents/Resources/SUPPORT.md"
cp "$MACOS_DIR/Dependencies/THIRD_PARTY_NOTICES.md" \
  "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$MACOS_DIR/Dependencies/ares.lock.json" \
  "$APP_DIR/Contents/Resources/ares.lock.json"

list_rpaths() {
  otool -l "$1" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
    in_rpath && $1 == "path" { print $2; in_rpath = 0 }
  '
}

if otool -l "$APP_DIR/Contents/MacOS/SwanSong" | grep -Fq "path $BUILD_DIR"; then
  install_name_tool -delete_rpath "$BUILD_DIR" \
    "$APP_DIR/Contents/MacOS/SwanSong"
fi

# SwiftPM can add the selected Command Line Tools or full-Xcode runtime
# directory while cross-compiling. macOS 14 supplies the Swift runtime;
# retaining any absolute developer-machine path would make the release bundle
# non-portable. `sort -u` is important because otool prints each universal2
# slice separately.
development_swift_rpaths=$(list_rpaths \
  "$APP_DIR/Contents/MacOS/SwanSong" \
  | grep -E '^/(Library/Developer/CommandLineTools|Applications/.*Xcode[^/]*)/.*swift' \
  | sort -u \
  || true)
while IFS= read -r rpath; do
  if [ -n "$rpath" ]; then
    install_name_tool -delete_rpath "$rpath" \
      "$APP_DIR/Contents/MacOS/SwanSong"
  fi
done <<EOF
$development_swift_rpaths
EOF

install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "$APP_DIR/Contents/MacOS/SwanSong"

if list_rpaths "$APP_DIR/Contents/MacOS/SwanSong" \
  | grep -Eq '^/(Library/Developer/CommandLineTools|Applications/.*Xcode[^/]*)/.*swift'; then
  echo "an absolute developer-toolchain Swift runtime rpath remains in the app" >&2
  exit 1
fi

if [ "$UNIVERSAL" = "1" ]; then
  "$SCRIPT_DIR/verify-app-architectures.sh" "$APP_DIR"
fi

sign_code "$APP_DIR/Contents/Frameworks/libSwanAresEngine.dylib"
sign_code "$APP_DIR"

codesign --verify --deep --strict "$APP_DIR"
if [ "$SIGNING_IDENTITY" = "-" ]; then
  echo "Built an ad-hoc-signed app bundle." >&2
else
  echo "Built a hardened-runtime app signed with: $SIGNING_IDENTITY" >&2
fi

echo "$APP_DIR"
