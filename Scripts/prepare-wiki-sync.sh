#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
SOURCE_DIR="$REPOSITORY_ROOT/docs/wiki"

usage() {
  echo "usage: $0 --check | --stage /path/to/SwanSong-Desktop.wiki" >&2
}

fail() {
  echo "wiki sync preparation failed: $1" >&2
  exit 1
}

validate_source() {
  [ -d "$SOURCE_DIR" ] || fail "docs/wiki source directory is missing"

  required_pages='0.2-Beta-Testing.md
0.3-Beta-Testing.md
0.4-Beta-Testing.md
0.5-Release-Testing.md
0.6-Release-Testing.md
Architecture-and-Source-Ownership.md
Build-and-Test.md
Cartridge-Lab.md
Gamepads.md
Home.md
Homebrew-Catalog.md
Open-IPL.md
Release-Gates.md
Story-Forge.md
SwanSong-Studio.md
_Sidebar.md'

  printf '%s\n' "$required_pages" | while IFS= read -r page; do
    [ -f "$SOURCE_DIR/$page" ] || fail "required page is missing: $page"
    [ ! -L "$SOURCE_DIR/$page" ] || fail "wiki page must not be a symlink: $page"
    [ -s "$SOURCE_DIR/$page" ] || fail "wiki page is empty: $page"
  done

  unexpected=$(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 \
    ! -type f -o -type f ! -name '*.md')
  [ -z "$unexpected" ] || fail "docs/wiki contains a non-page entry: $unexpected"

  find "$SOURCE_DIR" -maxdepth 1 -type f -name '*.md' -print | sort |
    while IFS= read -r page; do
      { grep -Eo '\[\[[^]]+\]\]' "$page" || true; } |
        sed -e 's/^\[\[//' -e 's/\]\]$//' |
        while IFS= read -r link; do
          case "$link" in
            *'|'*) title=${link##*|} ;;
            *) title=$link ;;
          esac
          slug=$(printf '%s' "$title" | tr ' ' '-')
          [ -f "$SOURCE_DIR/$slug.md" ] ||
            fail "$(basename "$page") links to missing wiki page: $title"
        done
    done

  echo "PASS repo-backed wiki source and internal page links"
}

stage_checkout() {
  checkout=$1
  source_origin=$(git -C "$REPOSITORY_ROOT" remote get-url origin 2>/dev/null || true)
  [ "$source_origin" = "https://github.com/RegionallyFamous/SwanSong-Desktop.git" ] ||
    fail "source origin is not RegionallyFamous/SwanSong-Desktop: $source_origin"

  source_branch=$(git -C "$REPOSITORY_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  [ "$source_branch" = "main" ] ||
    fail "source checkout must be on main before Wiki staging: ${source_branch:-detached}"
  [ -z "$(git -C "$REPOSITORY_ROOT" status --porcelain --untracked-files=all)" ] ||
    fail "source checkout must be clean before Wiki staging"
  source_remote_head=$(git -C "$REPOSITORY_ROOT" ls-remote --exit-code \
    origin refs/heads/main 2>/dev/null | awk 'NR == 1 { print $1 }')
  printf '%s\n' "$source_remote_head" | grep -Eq '^[0-9a-f]{40}$' ||
    fail "could not resolve the current origin/main commit"
  [ "$(git -C "$REPOSITORY_ROOT" rev-parse HEAD)" = \
    "$source_remote_head" ] ||
    fail "source main must exactly match origin/main before Wiki staging"
  for source_page in "$SOURCE_DIR"/*.md; do
    relative_page=${source_page#"$REPOSITORY_ROOT"/}
    git -C "$REPOSITORY_ROOT" ls-files --error-unmatch -- "$relative_page" \
      >/dev/null 2>&1 || fail "Wiki source page is not tracked: $relative_page"
  done

  [ -d "$checkout/.git" ] || fail "target is not a Git checkout: $checkout"

  checkout=$(CDPATH='' cd -- "$checkout" && pwd -P)
  [ "$checkout" != "$REPOSITORY_ROOT" ] || fail "refusing to stage into the Desktop source checkout"

  origin=$(git -C "$checkout" remote get-url origin 2>/dev/null || true)
  case "$origin" in
    https://github.com/RegionallyFamous/SwanSong-Desktop.wiki.git|\
    git@github.com:RegionallyFamous/SwanSong-Desktop.wiki.git)
      ;;
    *) fail "target origin is not RegionallyFamous/SwanSong-Desktop.wiki: $origin" ;;
  esac

  [ -z "$(git -C "$checkout" status --porcelain --untracked-files=all)" ] ||
    fail "target Wiki checkout is not clean"
  wiki_branch=$(git -C "$checkout" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  [ "$wiki_branch" = "master" ] ||
    fail "target Wiki checkout must be on master: ${wiki_branch:-detached}"
  wiki_upstream=$(git -C "$checkout" rev-parse --abbrev-ref \
    --symbolic-full-name '@{upstream}' 2>/dev/null || true)
  [ "$wiki_upstream" = "origin/master" ] ||
    fail "target Wiki master must track origin/master: ${wiki_upstream:-none}"
  wiki_remote_head=$(git -C "$checkout" ls-remote --exit-code \
    origin refs/heads/master 2>/dev/null | awk 'NR == 1 { print $1 }')
  printf '%s\n' "$wiki_remote_head" | grep -Eq '^[0-9a-f]{40}$' ||
    fail "could not resolve the current Wiki origin/master commit"
  [ "$(git -C "$checkout" rev-parse HEAD)" = "$wiki_remote_head" ] ||
    fail "target Wiki master must exactly match origin/master before staging"

  extra_pages=''
  for target_page in "$checkout"/*.md; do
    [ -e "$target_page" ] || continue
    name=$(basename "$target_page")
    if [ ! -f "$SOURCE_DIR/$name" ]; then
      extra_pages="${extra_pages}${extra_pages:+, }$name"
    fi
  done
  [ -z "$extra_pages" ] ||
    fail "target contains unmanaged Wiki pages; reconcile them explicitly: $extra_pages"

  for source_page in "$SOURCE_DIR"/*.md; do
    install -m 0644 "$source_page" "$checkout/$(basename "$source_page")"
  done

  echo "PASS staged repo-backed pages into $checkout"
  echo "Review before publishing: git -C '$checkout' diff --check && git -C '$checkout' diff"
  echo "This helper never commits or pushes the Wiki."
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}

case "$1" in
  --check)
    [ "$#" -eq 1 ] || {
      usage
      exit 2
    }
    validate_source
    ;;
  --stage)
    [ "$#" -eq 2 ] || {
      usage
      exit 2
    }
    validate_source
    stage_checkout "$2"
    ;;
  *)
    usage
    exit 2
    ;;
esac
