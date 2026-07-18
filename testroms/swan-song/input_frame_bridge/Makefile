# Reproducible Wonderful-toolchain build for SwanSong's input-frame fixture.

WONDERFUL_TOOLCHAIN ?= /opt/wonderful
TARGET = wswan/medium
include $(WONDERFUL_TOOLCHAIN)/target/$(TARGET)/makedefs.mk

BUILDDIR := build
ROM := input_frame_bridge.wsc
OBJECT := $(BUILDDIR)/main.c.o
ELF_STAGE := $(BUILDDIR)/stage1.elf

INCLUDEFLAGS := -I. -isystem $(WF_TARGET_DIR)/include
LIBDIRSFLAGS := -L$(WF_TARGET_DIR)/lib
CFLAGS += -std=gnu11 -Wall -Wextra -Werror $(WF_ARCH_CFLAGS) $(INCLUDEFLAGS) \
	-ffunction-sections -fdata-sections -fno-common -O2
LDFLAGS := -T$(WF_LDSCRIPT) $(LIBDIRSFLAGS) $(WF_ARCH_LDFLAGS) -lws

.PHONY: all clean

all: $(ROM)

$(ROM): $(ELF_STAGE) wfconfig.toml
	$(BUILDROM) -c wfconfig.toml -o $@ $<

$(ELF_STAGE): $(OBJECT)
	$(CC) -r -o $@ $< $(WF_CRT0) $(LDFLAGS)

$(OBJECT): main.c
	$(MKDIR) -p $(@D)
	$(CC) $(CFLAGS) -MMD -MP -c -o $@ $<

clean:
	$(RM) $(ROM) $(BUILDDIR)

-include $(OBJECT:.o=.d)
