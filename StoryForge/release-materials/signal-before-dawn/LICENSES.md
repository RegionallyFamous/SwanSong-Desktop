# Provenance And Licenses

This file distinguishes recorded provenance from permission to reuse a file.
A manifest hash or generation record is not a license grant.

## Original Project Content

The repository does not contain an explicit license grant for the original
`Signal Before Dawn` story, dialogue, characters, music, sound effects,
project-specific code changes, source art, generated art, release art, or
documentation. Do not assume an open-source or public-domain license for that
material. References to imagegen describe production provenance only; the
records do not identify a model/version or grant separate reuse rights.

The exact runtime-art derivations and hashes are recorded in
`reports/asset-provenance.json`. Release cover and label provenance is recorded
in `reports/release-art-report.json`; its physical print dimensions remain
`pending-real-cartridge-measurement`. Native review and ending evidence is
bound by `reports/native-scene-review-report.json` and the playthrough
manifest/report.

## Runtime Font

The ROM and release-art lettering use the upstream runtime file
`runtime/src/font.h`, SHA-256
`a097f12dc046bcf4de3ec96b2c9b502eea287e2e9fa9c81bd953d2efce18eade`.
Its header declares: "Public domain. Derived from a minimal bitmap font."
It is a fixed 8x8 ASCII table covering slots 32 through 127. No typeface name,
original font author, or more specific source is documented, so none is
claimed here.

## Upstream WSC VN Runtime

The base editor/runtime comes from
[maskofsin/Visual-Novel-Creator-for-Wonderswan](https://github.com/maskofsin/Visual-Novel-Creator-for-Wonderswan)
under the MIT License. Project-specific runtime changes are represented by the
packaged patch and are not given a separate license by this repository.

MIT License

Copyright (c) 2026 maskofsin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## WonderSwan System Libraries

The recorded build used Wonderful Toolchain `target-wswan 0.1.0-3`; its link
step uses the WonderSwan system libraries. The installed
`target-wswan-syslibs` package is licensed under the zlib License:

Copyright (c) 2022, 2023, 2024 Adrian "asie" Siekierka

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim
   that you wrote the original software. If you use this software in a
   product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.

## Build And Test Tools

These tools are recorded in the release evidence but are not distributed in
this archive:

- Wonderful Toolchain `target-wswan 0.1.0-3`, IA-16 GCC `6.3.0`, and
  `wf-tools`; individual components retain their own zlib, GPL, or MIT terms.
- Python `3.14.5`, under the
  [PSF License](https://docs.python.org/3/license.html).
- Pillow `12.3.0`, under the
  [MIT-CMU License](https://github.com/python-pillow/Pillow/blob/main/LICENSE).
- Mednafen `1.32.1`, under GPL-2.0-or-later.
- Mesen 2, under
  [GPL-3.0](https://github.com/SourMesen/Mesen2/blob/master/LICENSE).

See `reports/build-report.json`, `reports/emulator-smoke-report.json`, and the
playthrough report for the exact tools actually recorded for this build and
its captures.
