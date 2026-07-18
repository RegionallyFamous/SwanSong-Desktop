#!/bin/sh
set -eu

# Centralize SwiftPM launch options so normal local builds stay simple while
# restricted CI/agent environments can opt out of SwiftPM's nested sandbox.
command_name=${1:?SwiftPM subcommand is required}
shift

# Hosted CI and explicitly non-interactive local runs use only public,
# lockfile-pinned dependencies. Never let SwiftPM pause these lanes on a login
# keychain credential prompt.
if [ "${CI:-}" = "true" ] \
  || [ "${CI:-}" = "1" ] \
  || [ "${SWAN_SWIFTPM_DISABLE_KEYCHAIN:-0}" = "1" ]; then
  set -- --disable-keychain --only-use-versions-from-resolved-file "$@"
fi

# Some pre-release Apple toolchain updates can briefly install a compiler one
# patch newer than the matching SDK interfaces. This explicit, opt-in value is
# passed to both the package manifest and product compiler; release automation
# never guesses or silently overrides it.
if [ -n "${SWAN_SWIFT_INTERFACE_COMPILER_VERSION:-}" ] \
  && [ "${SWAN_SWIFTPM_DISABLE_SANDBOX:-0}" = "1" ]; then
  exec swift "$command_name" \
    --disable-sandbox \
    -Xbuild-tools-swiftc -interface-compiler-version \
    -Xbuild-tools-swiftc "$SWAN_SWIFT_INTERFACE_COMPILER_VERSION" \
    -Xswiftc -interface-compiler-version \
    -Xswiftc "$SWAN_SWIFT_INTERFACE_COMPILER_VERSION" \
    "$@"
fi

if [ -n "${SWAN_SWIFT_INTERFACE_COMPILER_VERSION:-}" ]; then
  exec swift "$command_name" \
    -Xbuild-tools-swiftc -interface-compiler-version \
    -Xbuild-tools-swiftc "$SWAN_SWIFT_INTERFACE_COMPILER_VERSION" \
    -Xswiftc -interface-compiler-version \
    -Xswiftc "$SWAN_SWIFT_INTERFACE_COMPILER_VERSION" \
    "$@"
fi

if [ "${SWAN_SWIFTPM_DISABLE_SANDBOX:-0}" = "1" ]; then
  exec swift "$command_name" --disable-sandbox "$@"
fi

exec swift "$command_name" "$@"
