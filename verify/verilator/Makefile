ROOT := $(abspath ../..)
VERILATOR ?= verilator
ELF64_OBJCOPY ?= loongarch64-linux-gnu-objcopy
JOBS ?= 0
VERILATOR_MAKEFLAGS ?= OPT_FAST=-O3
CONFIG_MMU ?= 0
CONFIG_MMU_RESOLVED := $(strip $(CONFIG_MMU))
CONFIG_MMU_SUPPORTED := 0 1
ifneq ($(words $(CONFIG_MMU_RESOLVED)),1)
$(error CONFIG_MMU must be exactly one integer from: $(CONFIG_MMU_SUPPORTED))
endif
ifeq ($(filter $(CONFIG_MMU_RESOLVED),$(CONFIG_MMU_SUPPORTED)),)
$(error CONFIG_MMU must be one of: $(CONFIG_MMU_SUPPORTED); got '$(CONFIG_MMU)')
endif
MMU_VERILATOR_DEFINE := $(if $(filter 1,$(CONFIG_MMU_RESOLVED)),-DCONFIG_MMU,)

CONFIG_SRAM ?= 1
CONFIG_SRAM_RESOLVED := $(strip $(CONFIG_SRAM))
CONFIG_SRAM_SUPPORTED := 0 1
ifneq ($(words $(CONFIG_SRAM_RESOLVED)),1)
$(error CONFIG_SRAM must be exactly one integer from: $(CONFIG_SRAM_SUPPORTED))
endif
ifeq ($(filter $(CONFIG_SRAM_RESOLVED),$(CONFIG_SRAM_SUPPORTED)),)
$(error CONFIG_SRAM must be one of: $(CONFIG_SRAM_SUPPORTED); got '$(CONFIG_SRAM)')
endif
SRAM_VERILATOR_DEFINE := $(if $(filter 1,$(CONFIG_SRAM_RESOLVED)),-DOPEN132_VERILATOR_SRAM,)

BUILD_DIR ?= $(CURDIR)/build
OBJ_DIR := $(BUILD_DIR)/obj_dir-mmu$(CONFIG_MMU_RESOLVED)-sram$(CONFIG_SRAM_RESOLVED)
EMU := $(BUILD_DIR)/emu-mmu$(CONFIG_MMU_RESOLVED)-sram$(CONFIG_SRAM_RESOLVED)

SRC_DIR := $(CURDIR)/src
VSRC_DIR := $(CURDIR)/vsrc
REF_INCLUDE := $(ROOT)/verify/loong-emu/include
RTL_FILELIST := $(ROOT)/design/filelist/openla132.f
TOP := $(VSRC_DIR)/verilator_top.sv
VERILATOR_HEADERS := $(VSRC_DIR)/soc_config.vh
COMMON_CONFIG := $(ROOT)/verify/apps/common/include/la_config.h

CPP_SOURCES := \
	$(SRC_DIR)/args.cpp \
	$(SRC_DIR)/axi.cpp \
	$(SRC_DIR)/check.cpp \
	$(SRC_DIR)/checkpoint.cpp \
	$(SRC_DIR)/diff_micro.cpp \
	$(SRC_DIR)/difftest.cpp \
	$(SRC_DIR)/elf_load.cpp \
	$(SRC_DIR)/ram.cpp \
	$(SRC_DIR)/ref_proxy.cpp \
	$(SRC_DIR)/uart.cpp \
	$(SRC_DIR)/verilator_main.cpp

RTL_RELATIVE := $(shell sed -n '/^[^+].*\.v$$/p' $(RTL_FILELIST))
RTL_SOURCES := $(addprefix $(ROOT)/,$(RTL_RELATIVE))

ifeq ($(CONFIG_SRAM_RESOLVED),1)
RTL_SOURCES += $(VSRC_DIR)/sram/openla132_spram_bytemask_init.v
endif

IMAGE ?= $(ROOT)/verify/apps/coremark/coremark.exe
REF ?= $(ROOT)/verify/loong-emu/build/la_emu_ref.so
LINUX_LOADER ?= $(ROOT)/impl/loader/loader.exe
LINUX_IMAGE ?= $(ROOT)/impl/loader/vmlinux.bin
LINUX_LOAD_ADDRESS ?= 0x00200000
COREMARK_MAX_CYCLES ?= 0xffffffff
RTTHREAD_DIR ?= $(ROOT)/verify/kernel/RTThread_Nano
RTTHREAD_SRAM_OBJDIR ?= $(RTTHREAD_DIR)/obj/sram
RTTHREAD_AXI_OBJDIR ?= $(RTTHREAD_DIR)/obj/axi
RTTHREAD_SRAM_IMAGE ?= $(RTTHREAD_SRAM_OBJDIR)/RTThread_Nano.elf
RTTHREAD_AXI_IMAGE ?= $(RTTHREAD_AXI_OBJDIR)/RTThread_Nano.elf
RTTHREAD_MAX_CYCLES ?= 0xffffffff
RTTHREAD_MAX_COMMITS ?= 0xffffffffffff
RUN_ARGS ?=
COREMARK_RUN_ARGS = $(if $(filter coremark.exe,$(notdir $(IMAGE))),--max-cycles $(COREMARK_MAX_CYCLES),)

# TAGE vs baseline-BTB IPC comparison (see `make compare-tage`).
BASE_REF ?= master
BASE_WORKTREE ?= $(BUILD_DIR)/baseline-$(BASE_REF)
COMPARE_MAX_COMMITS ?= 5000000
COMPARE_COREMARK ?= $(ROOT)/verify/apps/coremark/coremark.exe
COMPARE_DHRYSTONE ?= $(ROOT)/verify/apps/dhrystone/dhrystone.exe

VERILATOR_FLAGS ?= \
	--cc --exe --build \
	--top-module verilator_top \
	--Mdir $(OBJ_DIR) \
	--trace \
	--savable \
	-MAKEFLAGS "$(VERILATOR_MAKEFLAGS)" \
	-j $(JOBS) \
	-I$(ROOT)/design/sys/openla132/include \
	-I$(VSRC_DIR) \
	$(MMU_VERILATOR_DEFINE) \
	$(SRAM_VERILATOR_DEFINE) \
	-DOPEN132_OUTPUT_WB_STATE \
	-Wno-fatal \
	-Wno-PINMISSING \
	-Wno-UNUSEDSIGNAL \
	-Wno-UNUSEDPARAM \
	-Wno-MULTIDRIVEN \
	-Wno-UNOPTFLAT \
	-Wno-WIDTHEXPAND \
	-Wno-WIDTHTRUNC

CXXFLAGS ?= -O2 -g
CXXFLAGS += -std=c++17 -I$(SRC_DIR) -I$(REF_INCLUDE)
CXXFLAGS += -I$(ROOT)/verify/apps/common/include
CXXFLAGS += $(SRAM_VERILATOR_DEFINE)

.DEFAULT_GOAL := all

all: $(EMU)

$(EMU): $(CPP_SOURCES) $(SRC_DIR)/sim.h $(TOP) $(VERILATOR_HEADERS) $(COMMON_CONFIG) $(RTL_FILELIST) $(RTL_SOURCES)
	@mkdir -p $(BUILD_DIR)
	+cd $(ROOT) && $(VERILATOR) $(VERILATOR_FLAGS) \
		-o $(EMU) \
		$(RTL_SOURCES) \
		$(TOP) \
		$(CPP_SOURCES) \
		-CFLAGS "$(CXXFLAGS)" \
		-LDFLAGS "-ldl"

run: $(EMU)
	$(EMU) --diff --image $(IMAGE) --ref $(REF) $(COREMARK_RUN_ARGS) $(RUN_ARGS)

run-nodiff: $(EMU)
	$(EMU) --no-diff --image $(IMAGE) $(COREMARK_RUN_ARGS) $(RUN_ARGS)

run-coremark-sram:
	+$(MAKE) CONFIG_MMU=0 CONFIG_SRAM=1 \
		IMAGE="$(IMAGE)" COREMARK_MAX_CYCLES="$(COREMARK_MAX_CYCLES)" \
		RUN_ARGS="$(RUN_ARGS)" run-nodiff

run-rtthread-sram:
	+$(MAKE) -C $(RTTHREAD_DIR) OBJDIR="$(RTTHREAD_SRAM_OBJDIR)" HAS_CACHE=0
	+$(MAKE) CONFIG_MMU=0 CONFIG_SRAM=1 IMAGE="$(RTTHREAD_SRAM_IMAGE)" \
		RUN_ARGS="--max-cycles $(RTTHREAD_MAX_CYCLES) --max-commits $(RTTHREAD_MAX_COMMITS) $(RUN_ARGS)" \
		run-nodiff

run-rtthread-axi:
	+$(MAKE) -C $(RTTHREAD_DIR) OBJDIR="$(RTTHREAD_AXI_OBJDIR)" HAS_CACHE=1
	+$(MAKE) CONFIG_MMU=1 CONFIG_SRAM=0 IMAGE="$(RTTHREAD_AXI_IMAGE)" \
		RUN_ARGS="--max-cycles $(RTTHREAD_MAX_CYCLES) --max-commits $(RTTHREAD_MAX_COMMITS) $(RUN_ARGS)" \
		run-nodiff

linux: $(EMU)
	$(EMU) --diff --image $(LINUX_LOADER) --ref $(REF) \
		--load $(LINUX_IMAGE)@$(LINUX_LOAD_ADDRESS) $(RUN_ARGS)

linux-nodiff: $(EMU)
	$(EMU) --no-diff --image $(LINUX_LOADER) \
		--load $(LINUX_IMAGE)@$(LINUX_LOAD_ADDRESS) $(RUN_ARGS)

test: $(EMU)
	ELF64_OBJCOPY=$(ELF64_OBJCOPY) bash test/smoke.sh $(EMU) $(IMAGE) $(REF)

compare-tage: $(EMU)
	JOBS="$(JOBS)" bash test/compare_tage.sh \
		"$(EMU)" "$(BASE_REF)" "$(BASE_WORKTREE)" "$(ROOT)" \
		"coremark:$(COMPARE_COREMARK):$(COMPARE_MAX_COMMITS)" \
		"dhrystone:$(COMPARE_DHRYSTONE):$(COMPARE_MAX_COMMITS)"

clean:
	rm -rf $(BUILD_DIR)

help:
	@printf '%s\n' \
		'make                 Build the selected MMU/memory-interface model' \
		'make run             Run IMAGE with DiffTest enabled' \
		'make run-nodiff      Run IMAGE without DiffTest' \
		'make run-coremark-sram' \
		'                     Run CoreMark from inst_sram_*/data_sram_* only' \
		'make run-rtthread-sram' \
		'                     Build RT-Thread without cache and boot it from local SRAM' \
		'make run-rtthread-axi' \
		'                     Build RT-Thread with cache and boot it through MMU/system AXI' \
		'make linux           Boot the FPGA loader and Linux with DiffTest' \
		'make linux-nodiff    Boot the FPGA loader and Linux without DiffTest' \
		'make test            Run short no-diff and diff smoke tests' \
		'make compare-tage    Build BASE_REF (default master, original BTB) in a' \
		'                     worktree and print an IPC comparison for the images' \
		'                     in COMPARE_COREMARK/COMPARE_DHRYSTONE' \
		'make clean           Remove generated files' \
		'' \
		'Variables: CONFIG_MMU=0|1 CONFIG_SRAM=0|1 IMAGE=... REF=...' \
		'           COREMARK_MAX_CYCLES=2G RTTHREAD_MAX_CYCLES=1M' \
		'           RTTHREAD_MAX_COMMITS=300K RUN_ARGS="..." JOBS=N BUILD_DIR=...' \
		'           BASE_REF=master BASE_WORKTREE=... COMPARE_MAX_COMMITS=5M' \
		'           COMPARE_COREMARK=... COMPARE_DHRYSTONE=...'

.PHONY: all run run-nodiff run-coremark-sram run-rtthread-sram run-rtthread-axi linux linux-nodiff test compare-tage clean help
