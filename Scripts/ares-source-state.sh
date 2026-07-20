#!/bin/sh
set -eu

# Do not let an inherited developer PATH replace the identity tools. This
# helper is macOS-only and all required utilities are supplied by the system.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

if [ "$#" -ne 4 ]; then
  echo "usage: $0 write|check /path/to/ares-source COMMIT /path/to/ares-headless.patch" >&2
  exit 64
fi

ACTION=$1
SOURCE_INPUT=$2
COMMIT=$3
PATCH_INPUT=$4
SOURCE_DIR=$(CDPATH= cd -- "$SOURCE_INPUT" && pwd -P) || {
  echo "ares source directory is unavailable: $SOURCE_INPUT" >&2
  exit 1
}
PATCH_PARENT=$(CDPATH= cd -- "$(dirname -- "$PATCH_INPUT")" && pwd -P) || {
  echo "ares patch parent is unavailable: $PATCH_INPUT" >&2
  exit 1
}
PATCH="$PATCH_PARENT/$(basename -- "$PATCH_INPUT")"
STAMP="$SOURCE_DIR/.swan-song-ares-source-v1"
STAMP_BASENAME=.swan-song-ares-source-v1

case "$ACTION" in
  write|check) ;;
  *)
    echo "unknown ares source-state action '$ACTION' (use write or check)" >&2
    exit 64
    ;;
esac

printf '%s\n' "$COMMIT" | grep -Eq '^[0-9a-f]{40}$' || {
  echo "ares source commit is invalid" >&2
  exit 1
}
[ -d "$SOURCE_DIR" ] && [ ! -L "$SOURCE_DIR" ] || {
  echo "ares source directory is missing or is a symlink: $SOURCE_DIR" >&2
  exit 1
}
[ -f "$PATCH" ] && [ ! -L "$PATCH" ] || {
  echo "ares patch is missing or is not a regular file: $PATCH" >&2
  exit 1
}

PATCH_SHA256=$(shasum -a 256 "$PATCH" | awk '{ print $1 }')

# Bind every entry in the prepared tree, including Git administration data in
# managed checkouts. The canonical stream uses byte-sorted, length-delimited
# paths and payloads, so unusual path or symlink bytes cannot make two trees
# equivalent. Timestamps and non-executable permission bits are intentionally
# omitted: they are not build inputs and vary with archive extraction umasks.
# The executable bit is kept. The identity stamp itself is the only exclusion.
TEMP_STAMP=
PATCH_CHECK_LOG=$(mktemp "${TMPDIR:-/tmp}/swan-song-ares-reverse-check.XXXXXX")
cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  if [ -n "$TEMP_STAMP" ] && [ -f "$TEMP_STAMP" ]; then
    rm -f "$TEMP_STAMP"
  fi
  rm -f "$PATCH_CHECK_LOG"
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

tree_manifest_sha256() {
  if ! (
    cd "$SOURCE_DIR"
    /usr/bin/perl -MDigest::SHA -MFile::Find -MFcntl=:mode -MCwd=abs_path -e '
      use strict;
      use warnings;
      use bytes;

      my ($stamp) = @ARGV;
      my $root = abs_path(".");
      die "could not resolve prepared-tree root\n" unless defined $root;
      my @paths;
      File::Find::find(
        {
          no_chdir => 1,
          wanted => sub {
            my $path = $File::Find::name;
            return if $path eq "." || $path eq "./$stamp";
            push @paths, $path;
          },
        },
        "."
      );

      my $sha = Digest::SHA->new(256);
      $sha->add("swan-song-ares-tree-manifest-v1\0");

      for my $path (sort { $a cmp $b } @paths) {
        my @stat = lstat($path);
        die "could not inspect $path: $!\n" unless @stat;
        my $mode = $stat[2];
        my $path_record = length($path) . ":" . $path;

        if (S_ISDIR($mode)) {
          $sha->add("d", $path_record);
        } elsif (S_ISLNK($mode)) {
          my $target = readlink($path);
          die "could not read symlink $path: $!\n" unless defined $target;
          my $resolved = abs_path($path);
          die "broken prepared-tree symlink $path\n" unless defined $resolved;
          die "prepared-tree symlink escapes its root: $path\n"
            unless $resolved eq $root || index($resolved, "$root/") == 0;
          $sha->add("l", $path_record, length($target) . ":", $target);
        } elsif (S_ISREG($mode)) {
          open my $file, "<:raw", $path
            or die "could not open $path: $!\n";
          $sha->add("f", $path_record, ($mode & 0111) ? "1" : "0");
          $sha->add($stat[7] . ":");
          my $remaining = $stat[7];
          while ($remaining > 0) {
            my $read = read($file, my $buffer, $remaining > 1048576 ? 1048576 : $remaining);
            die "could not read $path: $!\n" unless defined $read;
            die "file changed while hashing $path\n" if $read == 0;
            $sha->add($buffer);
            $remaining -= $read;
          }
          my $extra_read = read($file, my $extra, 1);
          die "could not finish reading $path: $!\n" unless defined $extra_read;
          die "file changed while hashing $path\n" if $extra_read != 0;
          close $file or die "could not close $path: $!\n";
        } else {
          die "unsupported prepared-tree entry $path\n";
        }
      }

      print $sha->hexdigest, "\n";
    ' "$STAMP_BASENAME"
  ); then
    echo "could not inventory the complete prepared ares source tree" >&2
    exit 1
  fi
}

if [ -d "$SOURCE_DIR/.git" ] || [ -f "$SOURCE_DIR/.git" ]; then
  ACTUAL_COMMIT=$(/usr/bin/git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null || true)
  if [ "$ACTUAL_COMMIT" != "$COMMIT" ]; then
    echo "ares checkout mismatch: expected $COMMIT, found ${ACTUAL_COMMIT:-unknown}" >&2
    exit 1
  fi
fi

# This verifies the exact current patch still reverses cleanly from the source
# that will be compiled. It catches a forged or stale stamp as well as the
# common case where the tracked patch changed after an earlier preparation.
if ! (
  cd "$SOURCE_DIR"
  GIT_CEILING_DIRECTORIES=$(dirname -- "$SOURCE_DIR")
  export GIT_CEILING_DIRECTORIES
  /usr/bin/git apply --reverse --check --verbose "$PATCH"
) >"$PATCH_CHECK_LOG" 2>&1; then
  cat "$PATCH_CHECK_LOG" >&2
  echo "ares source does not contain the exact current headless patch" >&2
  exit 1
fi
if grep -F 'Skipped patch' "$PATCH_CHECK_LOG" >/dev/null 2>&1; then
  cat "$PATCH_CHECK_LOG" >&2
  echo "ares reverse check skipped at least one patch path" >&2
  exit 1
fi

TREE_SHA256=$(tree_manifest_sha256)
EXPECTED_STAMP=$(printf '%s\n' \
  'swan-song-ares-source-v2' \
  "commit=$COMMIT" \
  "patchSHA256=$PATCH_SHA256" \
  'treeManifest=swan-song-ares-tree-manifest-v1' \
  "treeSHA256=$TREE_SHA256")

if [ "$ACTION" = "write" ]; then
  TEMP_STAMP=$(mktemp "$SOURCE_DIR/.swan-song-ares-source-v1.tmp.XXXXXX")
  printf '%s\n' "$EXPECTED_STAMP" >"$TEMP_STAMP"
  mv -f "$TEMP_STAMP" "$STAMP"
  TEMP_STAMP=
  exit 0
fi

[ -f "$STAMP" ] && [ ! -L "$STAMP" ] || {
  echo "ares source identity stamp is missing; rematerialize the managed checkout before building" >&2
  exit 1
}
ACTUAL_STAMP=$(cat "$STAMP")
if [ "$ACTUAL_STAMP" != "$EXPECTED_STAMP" ]; then
  echo "ares source identity stamp is stale; rematerialize the managed checkout before building" >&2
  exit 1
fi
