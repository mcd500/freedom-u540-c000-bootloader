# Copyright (c) 2018 SiFive, Inc
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: GPL-2.0-or-later
# See the file LICENSE for further information

SHELL=/bin/bash -x
CROSSCOMPILE?=riscv64-unknown-elf-
CC=${CROSSCOMPILE}gcc
LD=${CROSSCOMPILE}ld
OBJCOPY=${CROSSCOMPILE}objcopy
OBJDUMP=${CROSSCOMPILE}objdump
CFLAGS=-I. -O2 -ggdb -march=rv64imafdc -mabi=lp64d -Wall -mcmodel=medany -mexplicit-relocs
CCASFLAGS=-I. -mcmodel=medany -mexplicit-relocs
LDFLAGS=-nostdlib -nostartfiles -static

# This is broken up to match the order in the original zsbl
# clkutils.o is there to match original zsbl, may not be needed
LIB_ZS1_O=\
	spi/spi.o \
	uart/uart.o \
	lib/version.o

LIB_ZS2_O=\
	clkutils/clkutils.o \
	gpt/gpt.o \
	lib/memcpy.o \
	sd/sd.o \

LIB_FS_O= \
	fsbl/start.o \
	fsbl/main.o \
	$(LIB_ZS1_O) \
	ememoryotp/ememoryotp.o \
	fsbl/ux00boot.o \
	clkutils/clkutils.o \
	gpt/gpt.o \
	fdt/fdt.o \
	sd/sd.o \
	lib/memcpy.o \
	lib/memset.o \
	lib/strcmp.o \
	lib/strlen.o \
	fsbl/dtb.o \
	

H=$(wildcard *.h */*.h)

all: zsbl.bin fsbl.bin

elf: zsbl.elf fsbl.elf

asm: zsbl.asm fsbl.asm

ifeq ($(findstring vc707,$(BOARD)),vc707)
bin:= zsbl.bin
hex:= $(BUILD_DIR)/zsbl.hex

dts := $(BUILD_DIR)/$(CONFIG_PROJECT).$(CONFIG).dts
clk := $(BUILD_DIR)/$(CONFIG_PROJECT).$(CONFIG).tl_clock.h
z_dtb := zsbl/ux00_zsbl.dtb
f_dtb := fsbl/ux00_fsbl.dtb
inc_clk :=-include $(clk)
CFLAGS += -DBOARD=$(BOARD)

$(clk): $(dts)
	awk '/tlclk {/ && !f{f=1; next}; f && match($$0, /^.*clock-frequency.*<(.*)>.*/, arr) { print "#define TL_CLK " arr[1] "UL"}' $< > $@.tmp
	mv $@.tmp $@

$(z_dtb): $(dts)
	dtc $^ -o $@ -O dtb

$(f_dtb): $(dts)
	dtc $^ -o $@ -O dtb
endif

ifeq ($(strip $(BOARD)),)
%.dtb: %.dts
	dtc $^ -o $@ -O dtb
endif

memory_o.lds: memory.lds
	$(CC) $(DEFINES) -E -P -o $@ -x c-header $^

lib/version.c:
	echo "const char *gitid = \"$(shell git describe --always --dirty)\";" > lib/version.c
	echo "const char *gitdate = \"$(shell git log -n 1 --date=short --format=format:"%ad.%h" HEAD)\";" >> lib/version.c
	echo "const char *gitversion = \"$(shell git rev-parse HEAD)\";" >> lib/version.c
#	echo "const char *gitstatus = \"$(shell git status -s )\";" >> lib/version.c

zsbl/ux00boot.o: ux00boot/ux00boot.c memory_o.lds
	$(CC) $(CFLAGS) -DUX00BOOT_BOOT_STAGE=0 -c -o $@ $^

zsbl.elf: $(clk) zsbl/start.o zsbl/main.o $(LIB_ZS1_O) zsbl/ux00boot.o $(LIB_ZS2_O) ux00_zsbl.lds
	$(CC) $(CFLAGS) $(LDFLAGS) $(inc_clk) -o $@ $(filter %.o,$^) -T$(filter %.lds,$^)

fsbl/ux00boot.o: ux00boot/ux00boot.c memory_o.lds
	$(CC) $(CFLAGS) -DUX00BOOT_BOOT_STAGE=1 -c -o $@ $^

fsbl.elf: $(LIB_FS_O) ux00_fsbl.lds
	$(CC) $(CFLAGS) $(LDFLAGS) $(inc_clk) -o $@ $(filter %.o,$^) -T$(filter %.lds,$^)

fsbl/dtb.o: fsbl/ux00_fsbl.dtb

zsbl/start.o: zsbl/ux00_zsbl.dtb

%.bin: %.elf
	$(OBJCOPY) -O binary $^ $@

%.asm: %.elf
	$(OBJDUMP) -S $^ > $@

%.o: %.S
	$(CC) $(CFLAGS) $(CCASFLAGS) -c $< -o $@

%.o: %.c $(H)
	$(CC) $(CFLAGS) $(inc_clk) -o $@ -c $<

ifeq ($(BOARD),$(filter vc707,$(BOARD)))
.PHONY: hex
hex: $(hex)

$(hex): $(bin)
	od -t x4 -An -w4 -v $< > $@

romgen := $(BUILD_DIR)/rom.v
$(romgen): $(hex)
	$(rocketchip_dir)/scripts/vlsi_rom_gen $(ROMCONF) $< > $@

.PHONY: romgen
romgen: $(romgen)
endif

clean::
	rm -f */*.o */*.dtb zsbl.bin zsbl.elf zsbl.asm fsbl.bin fsbl.elf fsbl.asm ${hex} lib/version.c memory_o.lds
