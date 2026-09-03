REPO_ROOT := ../..
NEORV32_HOME := $(REPO_ROOT)/lib/neorv32
# CPUはRV32IM(C拡張なし)のため既定はim。imcでビルドすると即トラップする。
TARGET := riscv32im-unknown-none-elf
APP := minios_hello
BUILD_DIR := build
ELF := target/$(TARGET)/release/$(APP)
BUILD_ELF := $(BUILD_DIR)/$(APP).elf
RAW_BIN := $(BUILD_DIR)/$(APP).bin
IMAGE_GEN := $(BUILD_DIR)/image_gen
EXE_BIN := $(BUILD_DIR)/neorv32_exe.bin
APP_VHD := $(REPO_ROOT)/build/generated/neorv32_application_image.vhd

.PHONY: image app-vhd clean

image: $(EXE_BIN)

app-vhd: $(APP_VHD)

$(BUILD_DIR):
	mkdir -p $@

$(ELF): Cargo.toml Cargo.lock link.x src/lib.rs src/main.rs
	cargo rustc --release --target $(TARGET) --bin $(APP) -- \
	  -C link-arg=-Tlink.x \
	  -C link-arg=--gc-sections

$(BUILD_ELF): $(ELF) | $(BUILD_DIR)
	cp $< $@

$(RAW_BIN): $(BUILD_ELF)
	rust-objcopy -O binary $< $@

$(IMAGE_GEN): $(NEORV32_HOME)/sw/image_gen/image_gen.c | $(BUILD_DIR)
	cc -O2 $< -o $@

$(EXE_BIN): $(RAW_BIN) $(IMAGE_GEN)
	$(IMAGE_GEN) -app_bin $(RAW_BIN) $@ $(APP)

$(APP_VHD): $(RAW_BIN) $(IMAGE_GEN)
	mkdir -p $(dir $@)
	$(IMAGE_GEN) -app_vhd $(RAW_BIN) $@ $(APP)

clean:
	cargo clean
	rm -rf $(BUILD_DIR)
