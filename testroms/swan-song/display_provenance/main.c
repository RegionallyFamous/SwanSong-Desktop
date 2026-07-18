// SPDX-License-Identifier: CC0-1.0
#include <stdint.h>
#include <string.h>
#include <wonderful.h>
#include <ws.h>
#include <ws/display.h>
#include <ws/system.h>

#ifndef PROVENANCE_PACKED
#define PROVENANCE_PACKED 0
#endif

/*
 * Clean-room display-provenance fixture introduced for ABI 6 and extended for
 * ABI 8 upstream cartridge-source tracing. The horizontal build uses planar
 * 4bpp tiles; the vertical build uses packed 4bpp tiles. Both expose isolated
 * final pixels from Screen 1, Screen 2, and a priority sprite.
 */

__attribute__((section(".iramcx_1800")))
ws_screen_t screen_1;

__attribute__((section(".iramcx_1000")))
ws_screen_t screen_2;

__attribute__((section(".iramcx_0e00")))
ws_sprite_table_t sprites;

/*
 * A deliberately distinctive ROM-resident tile. Tile 1 is reused across the
 * Screen 1 background so one selected pixel and pixels outside the requested
 * rectangle consume the same exact cartridge bytes.
 */
#if PROVENANCE_PACKED
static const volatile uint8_t source_tile_one[32] = {
    0x4b, 0x4b, 0x4b, 0x4b, 0x48, 0x7b, 0x48, 0x7b,
    0x49, 0x6b, 0x49, 0x6b, 0x4e, 0x1b, 0x4e, 0x1b,
    0x4f, 0x0b, 0x4f, 0x0b, 0x4c, 0x3b, 0x4c, 0x3b,
    0x4d, 0x2b, 0x4d, 0x2b, 0x42, 0xdb, 0x42, 0xdb,
};
#else
static const volatile uint8_t source_tile_one[32] = {
    0xa5, 0x5a, 0x5a, 0x5a, 0xdb, 0x18, 0x7e, 0x42,
    0xe7, 0x42, 0x18, 0x7e, 0xff, 0x00, 0x66, 0x99,
    0xbd, 0xdb, 0x42, 0x18, 0x81, 0x7e, 0x18, 0x42,
    0xc3, 0x3c, 0x66, 0x99, 0xaa, 0x55, 0xf0, 0x0f,
};
#endif

__attribute__((noinline))
static void copy_source_tile_one(void) {
    volatile uint8_t ws_iram *destination =
        (volatile uint8_t ws_iram *)WS_TILE_4BPP_MEM(1);
    for (uint8_t index = 0; index < sizeof(source_tile_one); index++) {
        destination[index] = source_tile_one[index] ^ 0x5a;
    }
}

static void fill_solid_tile(uint16_t tile_index, uint8_t color) {
    uint8_t ws_iram *bytes = (uint8_t ws_iram *)WS_TILE_4BPP_MEM(tile_index);
    for (uint8_t row = 0; row < 8; row++) {
#if PROVENANCE_PACKED
        const uint8_t packed = (uint8_t)((color << 4) | color);
        bytes[(uint16_t)row * 4 + 0] = packed;
        bytes[(uint16_t)row * 4 + 1] = packed;
        bytes[(uint16_t)row * 4 + 2] = packed;
        bytes[(uint16_t)row * 4 + 3] = packed;
#else
        bytes[(uint16_t)row * 4 + 0] = (color & 1) ? 0xff : 0x00;
        bytes[(uint16_t)row * 4 + 1] = (color & 2) ? 0xff : 0x00;
        bytes[(uint16_t)row * 4 + 2] = (color & 4) ? 0xff : 0x00;
        bytes[(uint16_t)row * 4 + 3] = (color & 8) ? 0xff : 0x00;
#endif
    }
}

int main(void) {
    ws_display_set_control(0);
    if (!ws_system_set_mode(
        PROVENANCE_PACKED ? WS_MODE_COLOR_4BPP_PACKED : WS_MODE_COLOR_4BPP
    )) {
        while (1) ia16_halt();
    }

    memset(&screen_1, 0, sizeof(screen_1));
    memset(&screen_2, 0, sizeof(screen_2));
    memset(&sprites, 0, sizeof(sprites));
    memset(WS_TILE_4BPP_MEM(0), 0, 4 * sizeof(ws_display_tile_4bpp_t));

    copy_source_tile_one(); /* Screen 1, palette 0, ROM-sourced red row. */
    fill_solid_tile(2, 2); /* Screen 2, palette 1, green. */
    fill_solid_tile(3, 3); /* Sprite palette 8, blue. */

    for (uint16_t index = 0; index < 32 * 32; index++) {
        screen_1.cell[index] = WS_SCREEN_ATTR_TILE(1)
            | WS_SCREEN_ATTR_PALETTE(0);
    }
    screen_2.row[6].cell[8] = WS_SCREEN_ATTR_TILE(2)
        | WS_SCREEN_ATTR_PALETTE(1);

    sprites.entry[0].attr = WS_SPRITE_ATTR_TILE(3)
        | WS_SPRITE_ATTR_PALETTE(0)
        | WS_SPRITE_ATTR_PRIORITY;
    sprites.entry[0].x = 128;
    sprites.entry[0].y = 48;

    WS_SCREEN_COLOR_MEM(0)[1] = WS_RGB(15, 0, 0);
    WS_SCREEN_COLOR_MEM(1)[2] = WS_RGB(0, 15, 0);
    WS_SPRITE_COLOR_MEM(0)[3] = WS_RGB(0, 0, 15);

    ws_display_set_screen_addresses(&screen_1, &screen_2);
    ws_display_set_sprite_address(&sprites);
    outportb(WS_SPR_FIRST_PORT, 0);
    outportb(WS_SPR_COUNT_PORT, 1);
    ws_display_set_control(
        WS_DISPLAY_CTRL_SCR1_ENABLE
            | WS_DISPLAY_CTRL_SCR2_ENABLE
            | WS_DISPLAY_CTRL_SPR_ENABLE
    );

    while (1) ia16_halt();
}
