# Yokoi hardware support payload

This directory contains Base64-wrapped, raw-DEFLATE-compressed builds of Yokoi
Boot's installer cartridge and Yokoi Cart Service. They are independently executable
WonderSwan programs and are not original Bandai firmware or commercial game
data.

The programs are licensed under GPL-3.0-or-later. Their exact corresponding
source, build instructions, protocol, attribution, upstream BootFriend
provenance, tests, and source logo are included in the verified
`SwanSong-Yokoi-Toolkit.zip` beside this notice. Preferred-form build source is
under the archive's `source/` directory.

SwanSong verifies the declared size and SHA-256 after decoding each artifact.
It also verifies the bounded corresponding-source archive and every member in
that archive against its internal manifest. This development payload remains
release-locked until the physical hardware matrix is completed.
The native macOS client implements the documented wire protocol independently;
the GPL-3 programs are distributed as separate data resources and execute only
on a user's WonderSwan.
