// SPDX-License-Identifier: CC0-1.0
#include <wonderful.h>

	.arch	i186
	.code16
	.intel_syntax noprefix

	/*
	 * This routine is copied to 0000:0400. Each REP prefix is byte 14 of a
	 * fixed 16-byte block, making the MOVSB opcode callers exactly 043f,
	 * 044f, 045f, and 046f. It never returns to ROM-backed code after the
	 * active mapper values are changed to the inactive controls.
	 */
	.section .iramc_0400,"ax",@progbits
	.global mapper_window_owner_matrix_commit
	.type mapper_window_owner_matrix_commit,@function
mapper_window_owner_matrix_commit:
	cli
	cld
	xor	ax, ax
	mov	es, ax
	mov	al, 0xe2
	out	0xc2, al
	mov	al, 0xe3
	out	0xc3, al
	mov	al, 0xff
	out	0xc0, al
	jmp	.Lcopy_window_2

	.org	0x30, 0x90
.Lcopy_window_2:
	mov	ax, 0x2000
	mov	ds, ax
	mov	si, 0x8000
	mov	di, 0x4020
	mov	cx, 4
	.byte	0xf3
	.global mapper_window_owner_matrix_read_window_2
mapper_window_owner_matrix_read_window_2:
	.byte	0xa4

	.org	0x40, 0x90
.Lcopy_window_3:
	mov	ax, 0x3000
	mov	ds, ax
	mov	si, 0x8000
	mov	di, 0x4040
	mov	cx, 4
	.byte	0xf3
	.global mapper_window_owner_matrix_read_window_3
mapper_window_owner_matrix_read_window_3:
	.byte	0xa4

	.org	0x50, 0x90
.Lcopy_window_4:
	mov	ax, 0x4000
	mov	ds, ax
	mov	si, 0x8000
	mov	di, 0x4060
	mov	cx, 4
	.byte	0xf3
	.global mapper_window_owner_matrix_read_window_4
mapper_window_owner_matrix_read_window_4:
	.byte	0xa4

	.org	0x60, 0x90
.Lcopy_window_f:
	mov	ax, 0xf000
	mov	ds, ax
	mov	si, 0x8000
	mov	di, 0x4080
	mov	cx, 4
	.byte	0xf3
	.global mapper_window_owner_matrix_read_window_f
mapper_window_owner_matrix_read_window_f:
	.byte	0xa4

	.org	0x70, 0x90
	mov	al, 0xe6
	out	0xc2, al
	mov	al, 0xe7
	out	0xc3, al
	mov	al, 0xfe
	out	0xc0, al
	xor	ax, ax
	mov	ds, ax
	in	al, 0xc2
	mov	byte ptr [0x04f0], al
	in	al, 0xc3
	mov	byte ptr [0x04f1], al
	in	al, 0xc0
	mov	byte ptr [0x04f2], al
	mov	byte ptr [0x04f3], 0xa5
.Lhalt:
	hlt
	jmp	.Lhalt
	.size mapper_window_owner_matrix_commit,.-mapper_window_owner_matrix_commit

	/* Active payloads, each with one opaque high-bit pixel in plane order. */
	.section .rom0_E2_8000,"aR",@progbits
	.global mapper_window_owner_matrix_source_window_2
mapper_window_owner_matrix_source_window_2:
	.byte	0x80, 0x00, 0x00, 0x00

	.section .rom1_E3_8000,"aR",@progbits
	.global mapper_window_owner_matrix_source_window_3
mapper_window_owner_matrix_source_window_3:
	.byte	0x00, 0x80, 0x00, 0x00

	.section .romL_FF_48000,"aR",@progbits
	.global mapper_window_owner_matrix_source_window_4
mapper_window_owner_matrix_source_window_4:
	.byte	0x00, 0x00, 0x80, 0x00

	.section .romL_FF_F8000,"aR",@progbits
	.global mapper_window_owner_matrix_source_window_f
mapper_window_owner_matrix_source_window_f:
	.byte	0x00, 0x00, 0x00, 0x80

	/* Byte-identical inactive-bank decoys for all four mapper families. */
	.section .rom0_E6_8000,"aR",@progbits
	.global mapper_window_owner_matrix_decoy_window_2
mapper_window_owner_matrix_decoy_window_2:
	.byte	0x80, 0x00, 0x00, 0x00

	.section .rom1_E7_8000,"aR",@progbits
	.global mapper_window_owner_matrix_decoy_window_3
mapper_window_owner_matrix_decoy_window_3:
	.byte	0x00, 0x80, 0x00, 0x00

	.section .romL_FE_48000,"aR",@progbits
	.global mapper_window_owner_matrix_decoy_window_4
mapper_window_owner_matrix_decoy_window_4:
	.byte	0x00, 0x00, 0x80, 0x00

	.section .romL_FE_F8000,"aR",@progbits
	.global mapper_window_owner_matrix_decoy_window_f
mapper_window_owner_matrix_decoy_window_f:
	.byte	0x00, 0x00, 0x00, 0x80

