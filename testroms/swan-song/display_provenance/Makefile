# Reproducible Wonderful-toolchain build for SwanSong's clean-room ABI 9
# provenance fixtures (also retaining the original ABI 6 owner checks).

WONDERFUL_TOOLCHAIN ?= /opt/wonderful
TARGET = wswan/medium
include $(WONDERFUL_TOOLCHAIN)/target/$(TARGET)/makedefs.mk

BUILDDIR := build
HORIZONTAL := display_provenance_horizontal.wsc
VERTICAL := display_provenance_vertical.wsc
HORIZONTAL_OBJECT := $(BUILDDIR)/horizontal/main.c.o
VERTICAL_OBJECT := $(BUILDDIR)/vertical/main.c.o
HORIZONTAL_STAGE := $(BUILDDIR)/horizontal/stage1.elf
VERTICAL_STAGE := $(BUILDDIR)/vertical/stage1.elf

INCLUDEFLAGS := -I. -isystem $(WF_TARGET_DIR)/include
LIBDIRSFLAGS := -L$(WF_TARGET_DIR)/lib
CFLAGS += -std=gnu11 -Wall -Wextra -Werror $(WF_ARCH_CFLAGS) $(INCLUDEFLAGS) \
	-ffunction-sections -fdata-sections -fno-common -O2
LDFLAGS := -T$(WF_LDSCRIPT) $(LIBDIRSFLAGS) $(WF_ARCH_LDFLAGS) -lws

.PHONY: all clean

all: $(HORIZONTAL) $(VERTICAL)

$(HORIZONTAL): $(HORIZONTAL_STAGE) wfconfig-horizontal.toml
	$(BUILDROM) -c wfconfig-horizontal.toml -o $@ $<

$(VERTICAL): $(VERTICAL_STAGE) wfconfig-vertical.toml
	$(BUILDROM) -c wfconfig-vertical.toml -o $@ $<

$(HORIZONTAL_STAGE): $(HORIZONTAL_OBJECT)
	$(CC) -r -o $@ $< $(WF_CRT0) $(LDFLAGS)

$(VERTICAL_STAGE): $(VERTICAL_OBJECT)
	$(CC) -r -o $@ $< $(WF_CRT0) $(LDFLAGS)

$(HORIZONTAL_OBJECT): main.c
	$(MKDIR) -p $(@D)
	$(CC) $(CFLAGS) -DPROVENANCE_PACKED=0 -MMD -MP -c -o $@ $<

$(VERTICAL_OBJECT): main.c
	$(MKDIR) -p $(@D)
	$(CC) $(CFLAGS) -DPROVENANCE_PACKED=1 -MMD -MP -c -o $@ $<

clean:
	$(RM) $(HORIZONTAL) $(VERTICAL) $(BUILDDIR)

-include $(HORIZONTAL_OBJECT:.o=.d) $(VERTICAL_OBJECT:.o=.d)
