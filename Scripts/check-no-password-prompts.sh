#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
case "$#" in
  0) ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd) ;;
  2)
    [ "$1" = "--test-root" ] || {
      echo "usage: $0 [--test-root DIRECTORY]" >&2
      exit 64
    }
    ROOT=$(CDPATH='' cd -- "$2" && pwd)
    ;;
  *)
    echo "usage: $0 [--test-root DIRECTORY]" >&2
    exit 64
    ;;
esac

RUNTIME_KEYCHAIN_MATCHES=$(grep -R -n -E \
  --include='*.swift' \
  'SecItem(Add|CopyMatching|Update|Delete)|SecKeychain|kSecUseAuthenticationUI|com\.regionallyfamous\.SwanSong\.HomebrewCatalogTrust' \
  "$ROOT/Sources/SwanSongApp" \
  "$ROOT/Sources/SwanSongKit" \
  "$ROOT/Sources/SwanSongRouteRunner" \
  "$ROOT/Tools/SwanSongMCP/Sources" 2>/dev/null || true)

if [ -n "$RUNTIME_KEYCHAIN_MATCHES" ]; then
  echo "runtime source reintroduced a login-Keychain path that can open a password dialog" >&2
  echo "$RUNTIME_KEYCHAIN_MATCHES" >&2
  exit 1
fi

grep -Fq -- '--disable-keychain' "$ROOT/Scripts/swift-package.sh" || {
  echo "the Swift package wrapper no longer disables Keychain lookup for non-interactive runs" >&2
  exit 1
}

for launcher in \
  "$ROOT/Scripts/run-swansong-mcp.sh" \
  "$ROOT/Scripts/run-swansong-playtest-mcp.sh"; do
  grep -Fq 'SWAN_SWIFTPM_DISABLE_KEYCHAIN=1' "$launcher" || {
    echo "a local automation launcher can consult the login Keychain: $launcher" >&2
    exit 1
  }
done

echo "PASS runtime and non-interactive local tools have no login-Keychain password path"
