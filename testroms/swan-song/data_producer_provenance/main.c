// SPDX-License-Identifier: CC0-1.0
#include <stdint.h>
#include <wonderful.h>
#include <ws.h>
#include <ws/memory.h>
#include <ws/system.h>

/* Distinctive ROM-resident bytes copied once into CPU-visible SRAM. */
const uint8_t __far producer_source[6] = {
    0x31, 0x7a, 0xc4, 0x09, 0xe2, 0x5d,
};

int main(void) {
    volatile uint8_t ws_sram *target = WS_SRAM_MEM + 0x3456;
    volatile const uint8_t __far *source = producer_source;
    for (uint8_t index = 0; index < sizeof(producer_source); ++index) {
        target[index] = source[index];
    }
    while (1) ia16_halt();
}
