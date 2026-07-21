# Reproducible Wonderful-toolchain build for SwanSong's clean-room ABI-10
# static-analysis seed-v2 retained-prefetch known-answer fixture.

WONDERFUL_TOOLCHAIN ?= /opt/wonderful
TARGET = wswan/medium
include $(WONDERFUL_TOOLCHAIN)/target/$(TARGET)/makedefs.mk

BUILDDIR := build
ROM := static_analysis_seed_v2.wsc
C_OBJECT := $(BUILDDIR)/main.c.o
S_OBJECT := $(BUILDDIR)/retained_fetch.s.o
ELF_STAGE := $(BUILDDIR)/stage1.elf
FINAL_ELF := $(BUILDDIR)/static_analysis_seed_v2.elf

INCLUDEFLAGS := -I. -isystem $(WF_TARGET_DIR)/include
LIBDIRSFLAGS := -L$(WF_TARGET_DIR)/lib
CFLAGS += -std=gnu11 -Wall -Wextra -Werror $(WF_ARCH_CFLAGS) $(INCLUDEFLAGS) \
	-ffunction-sections -fdata-sections -fno-common -O2
ASFLAGS += -x assembler-with-cpp $(WF_ARCH_CFLAGS) $(INCLUDEFLAGS) \
	-ffunction-sections -fdata-sections -fno-common
LDFLAGS := -T$(WF_LDSCRIPT) $(LIBDIRSFLAGS) $(WF_ARCH_LDFLAGS) -lws

.PHONY: all clean

all: $(ROM)

$(ROM): $(ELF_STAGE) wfconfig.toml
	$(BUILDROM) -c wfconfig.toml --output-elf $(FINAL_ELF) -o $@ $<

$(ELF_STAGE): $(C_OBJECT) $(S_OBJECT)
	$(CC) -r -o $@ $^ $(WF_CRT0) $(LDFLAGS)

$(C_OBJECT): main.c
	$(MKDIR) -p $(@D)
	$(CC) $(CFLAGS) -MMD -MP -c -o $@ $<

$(S_OBJECT): retained_fetch.s
	$(MKDIR) -p $(@D)
	$(CC) $(ASFLAGS) -MMD -MP -c -o $@ $<

clean:
	$(RM) $(ROM) $(BUILDDIR)

-include $(C_OBJECT:.o=.d) $(S_OBJECT:.o=.d)

