#!/bin/sh
if [ "$#" -ge 3 ] && [ "$1" = "--sdk" ] && [ "$3" = "--show-sdk-platform-version" ]; then
  exec /usr/bin/xcrun --sdk "$2" --show-sdk-version
fi
exec /usr/bin/xcrun "$@"
