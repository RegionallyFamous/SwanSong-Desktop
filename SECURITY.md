# Security policy

## Supported versions

Until the first stable release, security fixes target the latest published
pre-release and the default branch. After 1.0, the latest release line will be
supported unless its release notes say otherwise.

## Report a vulnerability privately

Use GitHub's **Report a vulnerability** flow in this repository's Security tab.
Please describe the affected version, expected and observed behavior, impact,
and the smallest safe reproduction you can provide.

Do not include game ROMs, system startup files, saves, save states, screenshots
containing private material, or Translation Lab evidence. A clean-room fixture
or written reproduction is preferred. Do not open a public issue for an
unfixed vulnerability.

We aim to acknowledge a report within seven days, provide an initial assessment
within fourteen days, and coordinate disclosure after a fix is available.

## Release verification

Official public binaries are published only from this repository's Releases
page. A public release must have all of the following:

- an exact `vX.Y.Z` source tag;
- a universal Apple silicon and Intel archive;
- a Developer ID Application signature with hardened runtime;
- an Apple notarization ticket accepted by Gatekeeper; and
- a matching entry in `SHA256SUMS.txt`.

If any item is missing, treat the download as a development artifact rather
than an official release.
