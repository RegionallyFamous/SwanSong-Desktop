// SPDX-License-Identifier: CC0-1.0
#include <stdint.h>
#include <string.h>
#include <wonderful.h>
#include <ws.h>
#include <ws/display.h>
#include <ws/dma.h>
#include <ws/system.h>

__attribute__((section(".iramcx_1800")))
ws_screen_t dma_screen;

/*
 * One distinctive ROM-resident planar row. The engine must retain these
 * cartridge origins while general DMA runs synchronously inside the OUT
 * instruction that sets WS_GDMA_CTRL_START.
 */
static const uint8_t __wf_rom __attribute__((aligned(2))) dma_source_tile[32] = {
    0x80, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
};

int main(void) {
    ws_display_set_control(0);
    if (!ws_system_set_mode(WS_MODE_COLOR_4BPP)) {
        while (1) ia16_halt();
    }

    memset(&dma_screen, 0, sizeof(dma_screen));
    memset(WS_TILE_4BPP_MEM(0), 0, sizeof(ws_display_tile_4bpp_t));
    ws_gdma_copy(WS_TILE_4BPP_MEM(1), dma_source_tile,
                 sizeof(dma_source_tile));

    dma_screen.row[1].cell[1] = WS_SCREEN_ATTR_TILE(1)
        | WS_SCREEN_ATTR_PALETTE(0);
    WS_SCREEN_COLOR_MEM(0)[1] = WS_RGB(15, 15, 15);
    ws_display_set_screen_addresses(&dma_screen, &dma_screen);
    ws_display_set_control(WS_DISPLAY_CTRL_SCR1_ENABLE);

    while (1) ia16_halt();
}
