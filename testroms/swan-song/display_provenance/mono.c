// SPDX-License-Identifier: CC0-1.0
#include <stdint.h>
#include <wonderful.h>
#include <ws.h>
#include <ws/display.h>

/*
 * Monochrome ABI-9 control fixture. The selected pixel at 0,0 is tile color 2
 * from palette 0. Pixel 9,0 is tile color 0 from palette 4 and must therefore
 * fall through to the backdrop. The final palette and display-control writes
 * are deliberately isolated in hand-written V30MZ assembly.
 */

__attribute__((section(".iramcx_1800")))
volatile uint16_t screen_1[32 * 32];

__attribute__((section(".iramx_2000")))
volatile uint16_t tile_words[8];

extern void mono_palette_out_owner_commit(void);

int main(void) {
    /* Volatile immediate stores give the selected map and raster exact owners. */
    screen_1[0] = WS_SCREEN_ATTR_TILE(0) | WS_SCREEN_ATTR_PALETTE(0);
    screen_1[1] = WS_SCREEN_ATTR_TILE(0) | WS_SCREEN_ATTR_PALETTE(4);
    tile_words[0] = 0x8000; /* Plane 1 bit 7: color 2 at local pixel 0. */

    mono_palette_out_owner_commit();

    while (1) {
        ia16_halt();
    }
}
