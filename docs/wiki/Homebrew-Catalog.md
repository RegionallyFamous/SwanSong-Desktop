# Homebrew Catalog

The first-party Homebrew Catalog is a small, signed shelf of WonderSwan games
that their publishers have affirmatively authorized SwanSong to distribute.
It is not a general ROM directory, a web search, or a background service.

SwanSong 0.4.2 and later include the published catalog and its
purpose-specific public key. Opening the Homebrew page still does not contact
the network.

## Browse only when you ask

SwanSong never loads the catalog at launch or merely because you opened the
Homebrew page.

1. Open **Homebrew**.
2. Choose **Browse Games** and review the short GitHub network disclosure.
3. Browse the verified entries.
4. Choose **Add to Library** for a title you want.
5. SwanSong downloads that one immutable release, verifies it, and adds it to
   the same private managed library as a local import.

**Refresh** is another explicit request. **Add From Mac** remains completely
local and available for authorized homebrew that is not in the catalog.

## What SwanSong verifies

Before an entry can appear as installable, SwanSong requires all of the
following to agree:

- the exact signed catalog bytes and trusted key ID;
- a supported, strict catalog schema and monotonically accepted revision;
- a known publisher with redistribution-rights and original-work attestations;
- immutable source, provenance, license, screenshot, and release references;
- the expected hardware and file format;
- the exact release asset byte count; and
- the ROM SHA-256 and WonderSwan content validation.

The catalog comes from the first-party
[`RegionallyFamous/swansong-catalog`](https://github.com/RegionallyFamous/swansong-catalog)
repository. Listed ROM releases remain immutable assets in their identified
source repositories. A signature or rights statement alone is never enough;
the whole entry must pass.

## Updates without losing the game you know

Catalog identities are stable. A compatible update keeps the library record,
favorite, artwork, play history, saves, and save states attached to the same
game.

SwanSong blocks an in-place update when the save contract or hardware changes.
Hash-changing Pocket Challenge V2 updates also stay blocked until program-flash
migration can preserve player data safely.

## Cache and rollback protection

An accepted catalog is stored in a private verified cache. SwanSong also keeps
a small Keychain high-water record so stopping catalog use and starting again
cannot make an older signed revision acceptable.

That automatic check never needs your login password. SwanSong binds new
records to the signed app identity used by future updates and explicitly
forbids Keychain authentication windows during launch. Legacy beta records are
left untouched and ignored, so an old permission cannot interrupt startup.

Catalog publication and cache updates are crash-safe and interprocess locked.
A delayed process must recheck the durable revision before it can publish
bytes, so two SwanSong processes cannot roll the accepted catalog backward.

Choosing **Stop Using Homebrew Catalog** removes consent and the saved catalog
copy but leaves installed games alone. The small anti-rollback record remains.

## Network and privacy boundary

Load and Refresh request the signed catalog and detached signature from GitHub.
Add to Library requests only the selected immutable game asset. SwanSong uses
no GitHub account, credential, or unique user identifier and does not attach
your library, saves, states, screenshots, compatibility notes, controller
settings, or Translation Lab data.

GitHub still receives ordinary connection information such as the connecting
IP address, request time, URL, and standard HTTP/TLS details. See the
[privacy policy](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/PRIVACY.md)
for the exact disclosure.

## Separate from app and Core updates

Sparkle updates `SwanSong.app`; it never installs a game. The Analogue Pocket
workflow installs an authorized SwanSong Core onto a card; it never loads this
catalog. The three features use different repositories, keys, schemas, consent,
storage, validation, and release gates. Trusting one cannot authorize another.
