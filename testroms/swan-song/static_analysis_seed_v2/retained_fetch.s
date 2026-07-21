// SPDX-License-Identifier: CC0-1.0
#include <wonderful.h>

	.arch	i186
	.code16
	.intel_syntax noprefix

	/*
	 * Establish the source/destination registers in fixed ROM, select bank
	 * E2, then far-jump into the mapper window. The far jump flushes any
	 * earlier prefetch state so the fixture begins from one explicit origin.
	 */
	.section .text.static_analysis_seed_v2_commit,"ax",@progbits
	.global static_analysis_seed_v2_commit
	.type static_analysis_seed_v2_commit,@function
static_analysis_seed_v2_commit:
	cli
	cld
	xor	ax, ax
	mov	es, ax
	mov	word ptr es:[0x4020], ax
	mov	word ptr es:[0x4022], ax
	mov	ax, 0x2000
	mov	ds, ax
	mov	si, 0x9000
	mov	di, 0x4020
	mov	cx, 2
	mov	al, 0xe2
	out	0xc2, al
	.byte	0xea
	.word	0x8000, 0x2000
	.size static_analysis_seed_v2_commit,.-static_analysis_seed_v2_commit

	/*
	 * Bank E2 owns the executed bytes. OUT selects E6, but the following F3 A5
	 * must already be in the V30MZ prefetch queue. E6 has F4 at the prefix
	 * address, so a refetch would halt before producing the pixel.
	 */
	.section .rom0_E2_8000,"aR",@progbits
	.global static_analysis_seed_v2_remap
static_analysis_seed_v2_remap:
	.byte	0xb0, 0xe6		/* mov al,0xe6 */
	.byte	0xe6, 0xc2		/* out 0xc2,al */
	.global static_analysis_seed_v2_retained_terminal
static_analysis_seed_v2_retained_terminal:
	.byte	0xf3, 0xa5		/* rep movsw, CX=2 */
	.byte	0xfa, 0xf4, 0xeb, 0xfd	/* cli; hlt; jmp hlt */

	.section .rom0_E6_8000,"aR",@progbits
	.global static_analysis_seed_v2_refetch_decoy
static_analysis_seed_v2_refetch_decoy:
	.byte	0xb0, 0xe6
	.byte	0xe6, 0xc2
	.byte	0xf4, 0xa5		/* hlt instead of rep movsw */
	.byte	0xfa, 0xf4, 0xeb, 0xfd

	/* The old bank contains a visible-byte decoy; only E6 contains 0x80. */
	.section .rom0_E2_9000,"aR",@progbits
	.global static_analysis_seed_v2_source_decoy
static_analysis_seed_v2_source_decoy:
	.byte	0x00, 0x00, 0x00, 0x00

	.section .rom0_E6_9000,"aR",@progbits
	.global static_analysis_seed_v2_visible_source
static_analysis_seed_v2_visible_source:
	.byte	0x80, 0x00, 0x00, 0x00
