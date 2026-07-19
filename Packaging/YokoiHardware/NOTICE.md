# Yokoi hardware support payload

This directory contains Base64-wrapped, raw-DEFLATE-compressed builds of Yokoi
Boot's installer cartridge and Yokoi Cart Service. They are independently executable
WonderSwan programs and are not original Bandai firmware or commercial game
data.

The programs are licensed under GPL-3.0-or-later. Their exact corresponding
source, build instructions, protocol, attribution, and upstream BootFriend
provenance are published under the firmware directory at commit
`94e9a1ae3d09f8d9eab776d36296144e85c72f1d`:

https://github.com/RegionallyFamous/swansong-core/tree/94e9a1ae3d09f8d9eab776d36296144e85c72f1d/firmware

SwanSong verifies the declared size and SHA-256 after decoding each artifact.
The native macOS client implements the documented wire protocol independently;
the GPL-3 programs are distributed as separate data resources and execute only
on a user's WonderSwan.
