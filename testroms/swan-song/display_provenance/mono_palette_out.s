// SPDX-License-Identifier: CC0-1.0
#include <wonderful.h>

	.arch	i186
	.code16
	.intel_syntax noprefix
	.text

	.global mono_palette_out_owner_commit
mono_palette_out_owner_commit:
	// Default monochrome shade LUT: 0, 2, 4, 6, 9, 11, 13, 15.
	mov	al, 0x20
	out	0x1c, al
	mov	al, 0x64
	out	0x1d, al
	mov	al, 0xb9
	out	0x1e, al
	mov	al, 0xfd
	out	0x1f, al

	// Palette 0 maps color 2 to shade 7. OUTW writes ports 0x20 and 0x21.
	mov	ax, 0x4720
	out	0x20, ax

	// White backdrop, Screen 1 map at 0x1800, then enable Screen 1 last.
	mov	al, 0x00
	out	0x01, al
	mov	al, 0x03
	out	0x07, al
	mov	al, 0x01
	out	0x00, al

	IA16_RET
