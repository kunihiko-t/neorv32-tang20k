# NEORV32 MiniOS Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tang Nano 20K向けNEORV32ビットストリームと、UARTへ文字を出すRV32IMC Rust実行形式を生成する。

**Architecture:** Tang Nano 20Kトップレベルはタイミングを満たす96MHzへ変更し、NEORV32ブートローダーは変更しない。依存クレートのないRustアプリを別ディレクトリに追加し、ホストテスト、クロスビルド、NEORV32 image generator、FPGA合成を順に検証する。

**Tech Stack:** Rust 1.98、RV32IMC、NEORV32、VHDL、Yosys/GHDL、nextpnr-himbaechel、gowin_pack、openFPGALoader

**Spec:** `docs/superpowers/specs/2026-09-01-neorv32-minios-spike-design.md`

## Global Constraints

- `/Users/valletta/dev/minios`は変更しない。
- Tang Nano 20Kのフラッシュへ書き込まない。
- macOSのFTDIドライバを無効化しない。
- 新規Rustクレート依存を追加しない。
- NEORV32は既存サブモジュールのコミット`fa0ea6904ffef7a7fa110102c1f587bf00a0955a`を使う。

---

### Task 1: Local toolchain and baseline

**Files:**
- Create: `/Users/valletta/dev/tang_nano_20k/.tools/oss-cad-suite/`
- Create: `script/env.sh`

**Interfaces:**
- Consumes: OSS CAD Suite Darwin arm64 release `2026-08-31`
- Produces: `yosys`、`ghdl`、`nextpnr-himbaechel`、`gowin_pack`、`rust-objcopy`をPATHへ追加する`script/env.sh`

- [x] **Step 1: Install the workspace-local FPGA toolchain**

  `oss-cad-suite-darwin-arm64-20260831.tgz`を`/Users/valletta/dev/tang_nano_20k/.tools/`へ展開する。参照Makefileのgrouped target構文に必要なGNU make 4系はHomebrewの`gmake`を使う。

- [x] **Step 2: Add the Rust target**

  Run: `rustup target add riscv32imc-unknown-none-elf`

- [x] **Step 3: Add the environment loader**

  `script/env.sh`はOSS CAD Suiteの`environment`をsourceし、XDGディレクトリとRust LLVMツールを作業フォルダ内から利用できるようにする。macOS 26で起動できないGHDLの重複RPATHとnextpnrラッパーの固定パスは、テスト付き修正スクリプトで補正する。

- [x] **Step 4: Verify exact tools**

  Run: `source script/env.sh && bash script/test-env.sh && bash script/test-ghdl-macos-rpath.sh && yosys -V && ghdl --version && nextpnr-himbaechel --version && gowin_pack --help >/dev/null && rust-objcopy --version`

  Expected: 全コマンドが終了コード0を返す。

- [x] **Step 5: Commit**

  ```bash
  git add docs script
  git commit -m "build: add local OSS CAD environment"
  ```

### Task 2: UART configuration library

**Files:**
- Create: `sw/minios_hello/Cargo.toml`
- Create: `sw/minios_hello/src/lib.rs`

**Interfaces:**
- Consumes: `clock_hz: u32`、`baud_rate: u32`
- Produces: `pub const fn uart_control(clock_hz: u32, baud_rate: u32) -> u32`

- [x] **Step 1: Write the failing test**

  `src/lib.rs`へ先に次のテストだけを書く。

  ```rust
  #[cfg(test)]
  mod tests {
      use super::uart_control;

      #[test]
      fn configures_system_uart_for_19200_baud() {
          assert_eq!(uart_control(96_000_000, 19_200), 0x0000_9c11);
      }
  }
  ```

- [x] **Step 2: Run test to verify it fails**

  Run: `cargo test --manifest-path sw/minios_hello/Cargo.toml`

  Expected: `uart_control`が存在しないためコンパイルに失敗する。

- [x] **Step 3: Implement the minimal UART divisor calculation**

  NEORV32の`neorv32_uart_setup`と同じプリスケーラ列`[2, 2, 8, 2, 4, 2, 2, 2]`を使い、enable、prescaler、10-bit divisorをCTRL値へ配置する。0Hzまたは0 baudは0を返す。

- [x] **Step 4: Verify green**

  Run: `cargo test --manifest-path sw/minios_hello/Cargo.toml`

  Expected: 3 tests passed, 0 failed。

- [x] **Step 5: Commit**

  ```bash
  git add sw/minios_hello/Cargo.toml sw/minios_hello/src/lib.rs
  git commit -m "feat: calculate NEORV32 UART configuration"
  ```

### Task 3: Bare-metal Rust executable and NEORV32 image

**Files:**
- Create: `sw/minios_hello/src/main.rs`
- Create: `sw/minios_hello/link.x`
- Create: `sw/minios_hello/Makefile`
- Create: `sw/minios_hello/tests/check_image.sh`

**Interfaces:**
- Consumes: UART0 base `0xFFF50000`、96MHz clock、19,200 baud
- Produces: `sw/minios_hello/build/minios_hello.elf`、`sw/minios_hello/build/neorv32_exe.bin`

- [x] **Step 1: Write the failing integration test**

  `tests/check_image.sh`は`make image`を実行し、`riscv32-unknown-elf-nm build/minios_hello.elf`に`_start`があり、`build/neorv32_exe.bin`が空でないことを検査する。

- [x] **Step 2: Run test to verify it fails**

  Run: `source script/env.sh && bash sw/minios_hello/tests/check_image.sh`

  Expected: `image`ターゲットがないため失敗する。

- [x] **Step 3: Add the minimal bare-metal program**

  `main.rs`は`global_asm!`で`sp=0x80003f40`を設定して`rust_main`を呼ぶ。`rust_main`はUART0 CTRLへ`uart_control(96_000_000, 19_200)`を書き、TX FIFO full（CTRL bit 21）が解除されるのを待って`MiniOS/RV32 hello\r\n`をDATA（base+4）へ1 byteずつ書く。

- [x] **Step 4: Add the linker and image build**

  `link.x`はIMEMを`0x00000000`から24,288 bytes、DMEMを`0x80000000`から16,192 bytesとして定義する。MakefileはCargo ELFから`.text`、`.rodata`、`.data`を順に抽出し、NEORV32の`sw/image_gen/image_gen.c`をホストでコンパイルして`-app_bin`形式を生成する。

- [x] **Step 5: Verify green**

  Run: `source script/env.sh && bash sw/minios_hello/tests/check_image.sh`

  Expected: `_start`が検出され、`neorv32_exe.bin`が生成される。

- [x] **Step 6: Commit**

  ```bash
  git add sw/minios_hello
  git commit -m "feat: build RV32IMC NEORV32 hello image"
  ```

### Task 4: Tang Nano 20K FPGA bitstream

**Files:**
- Modify: `README.md`
- Generated: `build/top.fs`

**Interfaces:**
- Consumes: 既存`src/hdl/top.vhd`とNEORV32サブモジュール
- Produces: Tang Nano 20K用SRAM転送可能ビットストリーム`build/top.fs`

- [x] **Step 1: Build the existing FPGA design**

  Run: `source script/env.sh && gmake bitstream summary`

  Expected: `build/top.fs`が生成され、タイミングとデバイス使用率のsummaryが終了コード0で出る。

- [x] **Step 2: Document safe commands**

  READMEへRust image生成、FPGA build、UARTポート確認、SRAM転送コマンドを追加する。SRAM転送は`openFPGALoader -b tangnano20k build/top.fs`だけを記載し、`-f`を含むコマンドは記載しない。

- [x] **Step 3: Verify documentation commands**

  Run: `source script/env.sh && cargo test --manifest-path sw/minios_hello/Cargo.toml && bash sw/minios_hello/tests/check_image.sh && gmake bitstream summary`

  Expected: すべて終了コード0。

- [x] **Step 4: Commit**

  ```bash
  git add README.md
  git commit -m "docs: add MiniOS spike build workflow"
  ```

### Task 5: Optional SRAM-only hardware check

**Files:** None

**Interfaces:**
- Consumes: `build/top.fs`、Tang Nano 20K
- Produces: 揮発性SRAM上で動くNEORV32ブートローダーのUART出力

- [ ] **Step 1: Re-check USB visibility**

  Run: `openFPGALoader --scan-usb`

  Expected: Tang Nano 20KのJTAGインターフェースが表示される。表示されなければここで停止する。

- [ ] **Step 2: Load SRAM only**

  Run only after Step 1 succeeds: `openFPGALoader -b tangnano20k build/top.fs`

  Expected: SRAM転送成功。電源再投入でフラッシュ上のNESTangへ戻る。

- [ ] **Step 3: Observe UART**

  19,200 baud、8-N-1で`/dev/cu.usbserial-20250303171`と`...170`を順に確認し、NEORV32ブートローダーのプロンプトを特定する。
