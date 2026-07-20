// SPDX-License-Identifier: CC0-1.0
#include <stdint.h>
#include <string.h>
#include <wonderful.h>
#include <ws.h>
#include <ws/display.h>
#include <ws/system.h>

__attribute__((section(".iramcx_1800")))
ws_screen_t blocked_screen;

static const volatile uint16_t blocked_raster_words[16] = {
    0xffff, 0xffff, 0xffff, 0xffff,
    0xffff, 0xffff, 0xffff, 0xffff,
    0xffff, 0xffff, 0xffff, 0xffff,
    0xffff, 0xffff, 0xffff, 0xffff,
};

__attribute__((noinline))
static void copy_through_unclassified_stack(uint16_t index) {
    uint16_t value = blocked_raster_words[index];
    __asm__ volatile(
        "push %0\n\t"
        "pop %0"
        : "+r"(value)
        :
        : "memory"
    );
    ((volatile uint16_t ws_iram *)WS_TILE_4BPP_MEM(1))[index] = value;
}

int main(void) {
    ws_display_set_control(0);
    if (!ws_system_set_mode(WS_MODE_COLOR_4BPP)) {
        while (1) ia16_halt();
    }
    memset(&blocked_screen, 0, sizeof(blocked_screen));
    for (uint16_t index = 0; index < 16; index++) {
        copy_through_unclassified_stack(index);
    }
    for (uint16_t index = 0; index < 32 * 32; index++) {
        blocked_screen.cell[index] = WS_SCREEN_ATTR_TILE(1)
            | WS_SCREEN_ATTR_PALETTE(0);
    }
    WS_SCREEN_COLOR_MEM(0)[15] = WS_RGB(15, 15, 15);
    ws_display_set_screen_addresses(&blocked_screen, &blocked_screen);
    ws_display_set_control(WS_DISPLAY_CTRL_SCR1_ENABLE);
    while (1) ia16_halt();
}
