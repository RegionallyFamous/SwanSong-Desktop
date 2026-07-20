# Reproducible Wonderful-toolchain build for SwanSong's clean-room ABI 9
# provenance fixtures (also retaining the original ABI 6 owner checks).

WONDERFUL_TOOLCHAIN ?= /opt/wonderful
TARGET = wswan/medium
include $(WONDERFUL_TOOLCHAIN)/target/$(TARGET)/makedefs.mk

BUILDDIR := build
HORIZONTAL := display_provenance_horizontal.wsc
VERTICAL := display_provenance_vertical.wsc
MONO := mono_palette_out_owner.ws
BLOCKED := source_lineage_blocked.wsc
HORIZONTAL_OBJECT := $(BUILDDIR)/horizontal/main.c.o
VERTICAL_OBJECT := $(BUILDDIR)/vertical/main.c.o
MONO_C_OBJECT := $(BUILDDIR)/mono/mono.c.o
MONO_S_OBJECT := $(BUILDDIR)/mono/mono_palette_out.s.o
BLOCKED_OBJECT := $(BUILDDIR)/blocked/blocked.c.o
HORIZONTAL_STAGE := $(BUILDDIR)/horizontal/stage1.elf
VERTICAL_STAGE := $(BUILDDIR)/vertical/stage1.elf
MONO_STAGE := $(BUILDDIR)/mono/stage1.elf
BLOCKED_STAGE := $(BUILDDIR)/blocked/stage1.elf

INCLUDEFLAGS := -I. -isystem $(WF_TARGET_DIR)/include
LIBDIRSFLAGS := -L$(WF_TARGET_DIR)/lib
CFLAGS += -std=gnu11 -Wall -Wextra -Werror $(WF_ARCH_CFLAGS) $(INCLUDEFLAGS) \
	-ffunction-sections -fdata-sections -fno-common -O2
ASFLAGS += -x assembler-with-cpp $(WF_ARCH_CFLAGS) $(INCLUDEFLAGS) \
	-ffunction-sections -fdata-sections -fno-common
LDFLAGS := -T$(WF_LDSCRIPT) $(LIBDIRSFLAGS) $(WF_ARCH_LDFLAGS) -lws

.PHONY: all clean

all: $(HORIZONTAL) $(VERTICAL) $(MONO) $(BLOCKED)

$(HORIZONTAL): $(HORIZONTAL_STAGE) wfconfig-horizontal.toml
	$(BUILDROM) -c wfconfig-horizontal.toml -o $@ $<

$(VERTICAL): $(VERTICAL_STAGE) wfconfig-vertical.toml
	$(BUILDROM) -c wfconfig-vertical.toml -o $@ $<

$(MONO): $(MONO_STAGE) wfconfig-mono.toml
	$(BUILDROM) -c wfconfig-mono.toml -o $@ $<

$(BLOCKED): $(BLOCKED_STAGE) wfconfig-horizontal.toml
	$(BUILDROM) -c wfconfig-horizontal.toml -o $@ $<

$(HORIZONTAL_STAGE): $(HORIZONTAL_OBJECT)
	$(CC) -r -o $@ $< $(WF_CRT0) $(LDFLAGS)

$(VERTICAL_STAGE): $(VERTICAL_OBJECT)
	$(CC) -r -o $@ $< $(WF_CRT0) $(LDFLAGS)

$(MONO_STAGE): $(MONO_C_OBJECT) $(MONO_S_OBJECT)
	$(CC) -r -o $@ $^ $(WF_CRT0) $(LDFLAGS)

$(BLOCKED_STAGE): $(BLOCKED_OBJECT)
	$(CC) -r -o $@ $< $(WF_CRT0) $(LDFLAGS)

$(HORIZONTAL_OBJECT): main.c
	$(MKDIR) -p $(@D)
	$(CC) $(CFLAGS) -DPROVENANCE_PACKED=0 -MMD -MP -c -o $@ $<

$(VERTICAL_OBJECT): main.c
	$(MKDIR) -p $(@D)
	$(CC) $(CFLAGS) -DPROVENANCE_PACKED=1 -MMD -MP -c -o $@ $<

$(MONO_C_OBJECT): mono.c
	$(MKDIR) -p $(@D)
	$(CC) $(CFLAGS) -MMD -MP -c -o $@ $<

$(MONO_S_OBJECT): mono_palette_out.s
	$(MKDIR) -p $(@D)
	$(CC) $(ASFLAGS) -MMD -MP -c -o $@ $<

$(BLOCKED_OBJECT): blocked.c
	$(MKDIR) -p $(@D)
	$(CC) $(CFLAGS) -MMD -MP -c -o $@ $<

clean:
	$(RM) $(HORIZONTAL) $(VERTICAL) $(MONO) $(BLOCKED) $(BUILDDIR)

-include $(HORIZONTAL_OBJECT:.o=.d) $(VERTICAL_OBJECT:.o=.d) \
	$(MONO_C_OBJECT:.o=.d) $(MONO_S_OBJECT:.o=.d) \
	$(BLOCKED_OBJECT:.o=.d)
