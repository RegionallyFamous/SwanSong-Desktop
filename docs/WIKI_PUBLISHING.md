# Publishing the SwanSong Desktop Wiki

The canonical Wiki source is tracked under [`docs/wiki/`](wiki/). Publishing is
a separate, reviewable Git operation because GitHub stores Wiki pages in the
`RegionallyFamous/SwanSong-Desktop.wiki` repository.

## Validate the tracked source

```sh
./Scripts/prepare-wiki-sync.sh --check
```

The check requires every canonical page and Sidebar entry, rejects symlinks or
non-Markdown payloads, and verifies internal `[[Wiki links]]` resolve.

## One-time GitHub initialization

If the GitHub Wiki has never been used, enable Wikis in the repository settings
and create its first page through the GitHub UI. GitHub does not expose the
`.wiki.git` clone endpoint until the Wiki is initialized. The staged tracked
`Home.md` will replace that temporary first page during the reviewed sync.

## Prepare a reviewable sync

After the documentation commit is merged, use a fresh, clean `main` checkout
whose `HEAD` exactly matches `origin/main`. Clone the Wiki outside that source
checkout, then stage the tracked pages:

```sh
git clone https://github.com/RegionallyFamous/SwanSong-Desktop.wiki.git \
  ../SwanSong-Desktop.wiki
./Scripts/prepare-wiki-sync.sh --stage ../SwanSong-Desktop.wiki
git -C ../SwanSong-Desktop.wiki diff --check
git -C ../SwanSong-Desktop.wiki diff
```

The helper verifies the exact Desktop and Wiki remotes, requires a clean source
`main` exactly equal to `origin/main`, requires every source page to be tracked,
refuses a dirty Wiki checkout, refuses unmanaged existing Markdown pages
instead of deleting them, and only copies the tracked page set. It never
commits or pushes.

After reviewing every page, publish manually with a commit that records the
Desktop source revision:

```sh
source_sha=$(git rev-parse HEAD)
git -C ../SwanSong-Desktop.wiki add -- '*.md'
git -C ../SwanSong-Desktop.wiki commit \
  -m "Sync Desktop Wiki from $source_sha"
git -C ../SwanSong-Desktop.wiki push origin HEAD:master
```

Reclone the Wiki after pushing and verify every canonical page is byte-identical
to `docs/wiki/`. Reopen the GitHub Wiki and verify Home, Sidebar navigation,
page links, and external repository links. Release documentation closure is
blocked until this validation, publication, and post-push verification pass;
public product claims must not diverge between release notes, repository docs,
and the published Wiki.
