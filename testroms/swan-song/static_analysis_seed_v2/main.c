// SPDX-License-Identifier: CC0-1.0
#include <stdint.h>
#include <string.h>
#include <wonderful.h>
#include <ws.h>
#include <ws/display.h>
#include <ws/system.h>

/*
 * One opaque Screen 1 pixel is produced only if the REP MOVSW prefetched from
 * mapper bank E2 survives the instruction's OUT-based remap to bank E6.
 * The two-element copy reads the complete four-byte raster owner from E6:9000
 * and writes it to 0000:4020 at the authenticated last-writer boundary.
 */

__attribute__((section(".iramcx_1800")))
ws_screen_t screen_1;

extern void static_analysis_seed_v2_commit(void)
    __attribute__((noreturn));

int main(void) {
    ws_display_set_control(0);
    if (!ws_system_set_mode(WS_MODE_COLOR_4BPP)) {
        while (1) ia16_halt();
    }

    memset(&screen_1, 0, sizeof(screen_1));
    memset(WS_TILE_4BPP_MEM(0), 0, 2 * sizeof(ws_display_tile_4bpp_t));

    screen_1.cell[0] = WS_SCREEN_ATTR_TILE(1)
        | WS_SCREEN_ATTR_PALETTE(0);
    WS_SCREEN_COLOR_MEM(0)[0] = WS_RGB(0, 0, 0);
    WS_SCREEN_COLOR_MEM(0)[1] = WS_RGB(15, 0, 0);

    ws_display_set_screen_addresses(&screen_1, &screen_1);
    ws_display_set_control(WS_DISPLAY_CTRL_SCR1_ENABLE);

    static_analysis_seed_v2_commit();
}
