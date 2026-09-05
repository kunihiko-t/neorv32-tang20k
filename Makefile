####################################################################################################
# Configuration
####################################################################################################
GOWIN_FAMILY = GW2A-18C
GOWIN_DEVICE = GW2AR-LV18QN88C8/I7
BOARD = tangnano20k
PACK_FLAGS = --jtag_as_gpio

TOP_MODULE = top
DESIGN = top
APP_VERILOG = SysPLL.v hdmi_console.v text_pixels.v uart_rx.v terminal_buffer.v
HDMI_VERILOG = diagnostics/hdmi/hdmi_timing.v diagnostics/hdmi/tmds_encode.v diagnostics/hdmi/video_pll.v
APP_VHDL = LEDBlink.vhd \
	BTNReset.vhd \
	top.vhd

NEORV32_VHDL = core/neorv32_package.vhd \
	core/neorv32_sys.vhd \
	core/neorv32_clockgate.vhd \
	core/neorv32_fifo.vhd \
	core/neorv32_cpu_decompressor.vhd \
	core/neorv32_cpu_frontend.vhd \
	core/neorv32_cpu_control.vhd \
	core/neorv32_cpu_counters.vhd \
	core/neorv32_cpu_regfile.vhd \
	core/neorv32_cpu_cp_shifter.vhd \
	core/neorv32_cpu_cp_muldiv.vhd \
	core/neorv32_cpu_cp_bitmanip.vhd \
	core/neorv32_cpu_cp_fpu.vhd \
	core/neorv32_cpu_cp_cfu.vhd \
	core/neorv32_cpu_cp_cond.vhd \
	core/neorv32_cpu_cp_crypto.vhd \
	core/neorv32_cpu_alu.vhd \
	core/neorv32_cpu_lsu.vhd \
	core/neorv32_cpu_pmp.vhd \
	core/neorv32_cpu_icc.vhd \
	core/neorv32_cpu.vhd \
	core/neorv32_cache.vhd \
	core/neorv32_bus.vhd \
	core/neorv32_dma.vhd \
	core/neorv32_application_image.vhd \
	core/neorv32_imem.vhd \
	core/neorv32_dmem.vhd \
	core/neorv32_xbus.vhd \
	core/neorv32_bootloader_image.vhd \
	core/neorv32_boot_rom.vhd \
	core/neorv32_cfs.vhd \
	core/neorv32_sdi.vhd \
	core/neorv32_gpio.vhd \
	core/neorv32_wdt.vhd \
	core/neorv32_clint.vhd \
	core/neorv32_uart.vhd \
	core/neorv32_spi.vhd \
	core/neorv32_twi.vhd \
	core/neorv32_twd.vhd \
	core/neorv32_pwm.vhd \
	core/neorv32_trng.vhd \
	core/neorv32_neoled.vhd \
	core/neorv32_gptmr.vhd \
	core/neorv32_onewire.vhd \
	core/neorv32_slink.vhd \
	core/neorv32_crc.vhd \
	core/neorv32_sysinfo.vhd \
	core/neorv32_debug_dtm.vhd \
	core/neorv32_debug_auth.vhd \
	core/neorv32_debug_dm.vhd \
	core/neorv32_top.vhd


SIMULATION_SETS = i2s_master \
    sine_generator clock_generator fpga_soc_top fpga_standalone_top

NTHREADS ?= 4
GOWIN_PACK ?= tabbypy3 script/pack_gowin.py

SW_FILE ?= neorv32_exe.bin
APP_IMAGE = build/generated/neorv32_application_image.vhd
APP_SOURCES = sw/minios_hello/Cargo.toml sw/minios_hello/Cargo.lock \
	sw/minios_hello/link.x sw/minios_hello/src/lib.rs sw/minios_hello/src/main.rs

####################################################################################################
# Abbreviations
####################################################################################################
OBJDIR=build
RPTDIR=$(OBJDIR)/rpt
SRCDIR=src
CONDIR=$(SRCDIR)/constraints
HDLDIR=$(SRCDIR)/hdl
NEORVDIR=lib/neorv32/rtl

####################################################################################################
# Generated variables
####################################################################################################
SIM_SETS=$(addsuffix .sim,$(SIMULATION_SETS))
SYN_VERILOG_PATHS=$(addprefix $(HDLDIR)/,$(APP_VERILOG)) $(HDMI_VERILOG)
SYN_VHDL_PATHS=$(addprefix $(HDLDIR)/,$(APP_VHDL)) \
	$(subst $(NEORVDIR)/core/neorv32_application_image.vhd,$(APP_IMAGE),$(addprefix $(NEORVDIR)/,$(NEORV32_VHDL)))

QUIET_FLAG=
ifeq ($(strip $(VERBOSE)),)
	QUIET_FLAG=-q
endif

####################################################################################################
# Tool Commands
####################################################################################################
SCRIPT_SUMMARY="$(abspath ./script/summary.py)"

####################################################################################################
# Rules
####################################################################################################
.PHONY: all synth pnr bitstream summary upload test-reset test-console uart-probe hdmi-probe
.PHONY: test-sd sd-probe-firmware

test-sd:
	mkdir -p build/test
	rustc --edition 2021 --test diagnostics/sd_probe/lib.rs -o build/test/sd_probe
	build/test/sd_probe

sd-probe-firmware:
	mkdir -p build/sd_probe
	rustc --edition 2021 --crate-name sd_probe --crate-type rlib --target riscv32im-unknown-none-elf \
	  -C opt-level=s -C panic=abort diagnostics/sd_probe/lib.rs -o build/sd_probe/libsd_probe.rlib
	rustc --edition 2021 --target riscv32im-unknown-none-elf -C opt-level=s -C panic=abort \
	  -C link-arg=-Tdiagnostics/sd_probe/link.x --extern sd_probe=build/sd_probe/libsd_probe.rlib \
	  diagnostics/sd_probe/main.rs -o build/sd_probe/probe.elf
.PRECIOUS: $(OBJDIR)/%.syn.json $(OBJDIR)/%.pnr.json

# High-level wrapper targets
all: bitstream summary
sim: $(SIM_SETS)

clean:
	rm -rf $(OBJDIR)

synth: $(OBJDIR)/$(DESIGN).syn.json

pnr: $(OBJDIR)/$(DESIGN).pnr.json

bitstream: $(OBJDIR)/$(DESIGN).fs

summary: $(RPTDIR)/$(DESIGN).pnr.json
	@echo
	@echo ========================== Device Summary ==========================
	@echo
	@$(SCRIPT_SUMMARY) $<

upload:
	openFPGALoader -b $(BOARD) $(OBJDIR)/$(DESIGN).fs

upload-flash:
	openFPGALoader -b $(BOARD) -f $(OBJDIR)/$(DESIGN).fs

upload-app-flash:
	openFPGALoader -b $(BOARD) -o 0x400000 -f $(SW_FILE)

test-reset:
	mkdir -p $(OBJDIR)/test
	cd $(OBJDIR)/test && ghdl -a --std=08 ../../src/hdl/BTNReset.vhd ../../test/BTNReset_tb.vhd
	cd $(OBJDIR)/test && ghdl -e --std=08 BTNReset_tb
	cd $(OBJDIR)/test && ghdl -r --std=08 BTNReset_tb --stop-time=200ns

test-console:
	mkdir -p $(OBJDIR)/test
	iverilog -g2012 -s tb_console -o $(OBJDIR)/test/console test/console_tb.v src/hdl/uart_rx.v src/hdl/terminal_buffer.v
	vvp $(OBJDIR)/test/console
	iverilog -g2012 -I diagnostics/hdmi -s text_pixels_tb -o $(OBJDIR)/test/text_pixels test/text_pixels_tb.v src/hdl/text_pixels.v
	vvp $(OBJDIR)/test/text_pixels
	tabbypy3 -m unittest discover -s test -p 'test_pack_gowin.py'

uart-probe: $(OBJDIR)/uart_probe/uart_probe.fs

hdmi-probe: $(OBJDIR)/hdmi/hdmi_probe.fs

$(OBJDIR)/hdmi/hdmi_probe.fs: diagnostics/hdmi/hdmi_probe.v \
		diagnostics/hdmi/hdmi_timing.v diagnostics/hdmi/tmds_encode.v \
		diagnostics/hdmi/video_pll.v diagnostics/hdmi/hdmi_probe.cst diagnostics/hdmi/hdmi_probe.py
	mkdir -p $(OBJDIR)/hdmi
	yosys -p "read_verilog diagnostics/hdmi/hdmi_probe.v diagnostics/hdmi/hdmi_timing.v diagnostics/hdmi/tmds_encode.v diagnostics/hdmi/video_pll.v; synth_gowin -top hdmi_probe -json $(OBJDIR)/hdmi/hdmi_probe.json"
	nextpnr-himbaechel --device $(GOWIN_DEVICE) --json $(OBJDIR)/hdmi/hdmi_probe.json \
	  --write $(OBJDIR)/hdmi/hdmi_probe_pnr.json --vopt family=$(GOWIN_FAMILY) \
	  --vopt cst=diagnostics/hdmi/hdmi_probe.cst --pre-pack diagnostics/hdmi/hdmi_probe.py
	gowin_pack -d $(GOWIN_FAMILY) -o $@ $(OBJDIR)/hdmi/hdmi_probe_pnr.json

$(OBJDIR)/uart_probe/uart_probe.fs: diagnostics/uart_probe/uart_probe.v \
		diagnostics/uart_probe/uart_probe.cst diagnostics/uart_probe/uart_probe.py
	mkdir -p $(OBJDIR)/uart_probe
	yosys -p "read_verilog diagnostics/uart_probe/uart_probe.v; synth_gowin -top uart_probe -json $(OBJDIR)/uart_probe/uart_probe.json"
	nextpnr-himbaechel --device $(GOWIN_DEVICE) --json $(OBJDIR)/uart_probe/uart_probe.json \
	  --write $(OBJDIR)/uart_probe/uart_probe_pnr.json --vopt family=$(GOWIN_FAMILY) \
	  --vopt cst=diagnostics/uart_probe/uart_probe.cst --pre-pack diagnostics/uart_probe/uart_probe.py
	gowin_pack -d $(GOWIN_FAMILY) -o $@ $(OBJDIR)/uart_probe/uart_probe_pnr.json

$(OBJDIR):
	mkdir -p $(OBJDIR)

$(RPTDIR):
	mkdir -p $(RPTDIR)

$(APP_IMAGE): $(APP_SOURCES)
	$(MAKE) -C sw/minios_hello app-vhd


####################################################################################################
# Automatic rule patterns: Create output(s) from input(s)
####################################################################################################

# Synthesis. TODO: Support multiple source sets / targets?
$(OBJDIR)/%.syn.json: $(SYN_VERILOG_PATHS) $(SYN_VHDL_PATHS) diagnostics/hdmi/font_init.vh | $(OBJDIR) $(RPTDIR)
	yosys -m ghdl -p "ghdl --work=neorv32 $(SYN_VHDL_PATHS) -e $(TOP_MODULE); read_verilog -I diagnostics/hdmi $(SYN_VERILOG_PATHS); synth_gowin -top $(TOP_MODULE) -json $@" \
	  $(QUIET_FLAG) -l $(RPTDIR)/$*.syn.log --detailed-timing

# Place and route
$(OBJDIR)/%.pnr.json $(RPTDIR)/%.pnr.json &: $(OBJDIR)/%.syn.json $(CONDIR)/%.cst $(CONDIR)/%.py | $(OBJDIR) $(RPTDIR) 
	nextpnr-himbaechel --device $(GOWIN_DEVICE) --json $(OBJDIR)/$*.syn.json --write $(OBJDIR)/$*.pnr.json \
	  --report $(RPTDIR)/$*.pnr.json --vopt family=$(GOWIN_FAMILY) \
	  --vopt cst=$(CONDIR)/$*.cst --pre-pack $(CONDIR)/$*.py $(QUIET_FLAG) -l $(RPTDIR)/$*.pnr.log \
	  --threads $(NTHREADS) --detailed-timing-report

# Bitstream generation / Packing
$(OBJDIR)/%.fs: $(OBJDIR)/%.pnr.json script/pack_gowin.py | $(OBJDIR)
	$(GOWIN_PACK) -d $(GOWIN_FAMILY) $(PACK_FLAGS) -o $@ $<
