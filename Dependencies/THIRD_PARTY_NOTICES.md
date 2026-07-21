# Third-party notices

This inventory covers the code linked by SwanSong's WonderSwan-only engine
configuration. The corresponding ares source is available from
<https://github.com/ares-emulator/ares> at the exact revision listed below.

## ares, nall, and libco

Copyright (c) 2004-2025 ares team, Near et al

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER
RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE
USE OR PERFORMANCE OF THIS SOFTWARE.

Source revision: `449b93716fb162632de2fd43bf2eba2064fa43f2`.

## Sparkle 2

SwanSong uses Sparkle for signed application updates. Sparkle 2.9.4 is pinned
to source revision `b6496a74a087257ef5e6da1c5b29a447a60f5bd7`. Its complete license and
bundled third-party notices are reproduced in `SPARKLE_LICENSE` and in the
application's Resources directory. Exact source is included in every official
corresponding-source archive under `Dependencies/sparkle-source`.

## SwanSong SDK

SwanSong Studio embeds the MIT-licensed SwanSong SDK 0.5.0 runtime, recipes,
schema, and Python package from revision
`f9bab7451593d0d8640816c60e0836377c65027e`. Its complete license and notices
are included inside the signed application at `Resources/SwanSongSDK`.

## Yokoi Boot and Yokoi Cart Service

SwanSong includes separately encoded WonderSwan programs for installing the
Yokoi Boot custom-splash loader and running Yokoi Cart Service from RAM. They
are GPL-3.0-or-later programs derived in part from Adrian Siekierka's
BootFriend. They are not linked into SwanSong and contain no original Bandai
firmware or commercial game data. Their complete GPLv3 license, notices,
verified artifact manifest, and corresponding-source location are included at
`Resources/YokoiHardware`. The corresponding Yokoi source is pinned to
SwanSong Core revision
`94e9a1ae3d09f8d9eab776d36296144e85c72f1d`.

## Stack-less Just-In-Time compiler (SLJIT)

Copyright Zoltan Herczeg. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

## Deliberate exclusions

The ares desktop UI, other emulator cores, CHD support, and their optional
dependencies are not linked. SwanSong's GPL-2.0 FPGA RTL is used as an
independent test oracle and is not linked or copied into the ares adapter.
