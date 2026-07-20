// SPDX-License-Identifier: CC0-1.0
#include <stdint.h>
#include <string.h>
#include <wonderful.h>
#include <ws.h>
#include <ws/display.h>
#include <ws/system.h>

/*
 * Clean-room ABI-9 mapper fixture. Four isolated Screen 1 pixels are loaded
 * from cartridge windows 2, 3, 4, and F by a fixed hand-written V30MZ
 * routine. Byte-identical inactive-bank decoys make content matching an
 * invalid substitute for executed mapper context.
 */

__attribute__((section(".iramcx_1800")))
ws_screen_t screen_1;

extern void mapper_window_owner_matrix_commit(void)
    __attribute__((noreturn));

int main(void) {
    ws_display_set_control(0);
    if (!ws_system_set_mode(WS_MODE_COLOR_4BPP)) {
        while (1) ia16_halt();
    }

    memset(&screen_1, 0, sizeof(screen_1));
    memset(WS_TILE_4BPP_MEM(0), 0, 5 * sizeof(ws_display_tile_4bpp_t));

    screen_1.cell[0] = WS_SCREEN_ATTR_TILE(1) | WS_SCREEN_ATTR_PALETTE(0);
    screen_1.cell[1] = WS_SCREEN_ATTR_TILE(2) | WS_SCREEN_ATTR_PALETTE(0);
    screen_1.cell[2] = WS_SCREEN_ATTR_TILE(3) | WS_SCREEN_ATTR_PALETTE(0);
    screen_1.cell[3] = WS_SCREEN_ATTR_TILE(4) | WS_SCREEN_ATTR_PALETTE(0);

    WS_SCREEN_COLOR_MEM(0)[0] = WS_RGB(0, 0, 0);
    WS_SCREEN_COLOR_MEM(0)[1] = WS_RGB(15, 0, 0);
    WS_SCREEN_COLOR_MEM(0)[2] = WS_RGB(0, 15, 0);
    WS_SCREEN_COLOR_MEM(0)[4] = WS_RGB(0, 0, 15);
    WS_SCREEN_COLOR_MEM(0)[8] = WS_RGB(15, 15, 0);

    ws_display_set_screen_addresses(&screen_1, &screen_1);
    ws_display_set_control(WS_DISPLAY_CTRL_SCR1_ENABLE);

    mapper_window_owner_matrix_commit();
}

