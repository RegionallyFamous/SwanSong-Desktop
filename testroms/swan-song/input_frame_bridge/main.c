// SPDX-License-Identifier: CC0-1.0
#include <stdint.h>
#include <wonderful.h>
#include <ws.h>

enum {
    INPUT_TRACE_MAGIC = 0x5349,
    INPUT_TRACE_READY = 0xa55a,
    INPUT_TRACE_CAPACITY = 16
};

typedef struct input_trace {
    uint16_t magic;
    uint16_t ready;
    uint16_t count;
    uint16_t samples[INPUT_TRACE_CAPACITY];
} input_trace_t;

__attribute__((section(".iramcx_1000")))
static volatile input_trace_t input_trace;

int main(void) {
    uint16_t last;
    uint8_t index;

    input_trace.magic = INPUT_TRACE_MAGIC;
    input_trace.ready = 0;
    input_trace.count = 0;
    for (index = 0; index < INPUT_TRACE_CAPACITY; ++index) {
        input_trace.samples[index] = 0xffff;
    }

    last = ws_keypad_scan();
    input_trace.ready = INPUT_TRACE_READY;
    ws_int_set_default_handler_vblank();
    ws_int_enable(WS_INT_ENABLE_VBLANK);
    ia16_enable_irq();
    while (1) {
        ia16_halt();
        const uint16_t current = ws_keypad_scan();
        if (current != last) {
            const uint16_t count = input_trace.count;
            if (count < INPUT_TRACE_CAPACITY) {
                input_trace.samples[count] = current;
                input_trace.count = count + 1;
            }
            last = current;
        }
    }
}
