# NEORV32 MiniOS Spike Design

## Goal

Tang Nano 20K上でMiniOS移植の前提となるNEORV32のビルド経路と、RV32IMC Rustプログラムの生成経路を確立する。

## Scope

- `jpf91/neorv32-tang20k`の固定済みNEORV32サブモジュールを基準にする。
- Rust製の最小プログラムはUART0へ`MiniOS/RV32 hello\r\n`を出力する。
- RustプログラムはNEORV32ブートローダーが受け取れる`neorv32_exe.bin`へ変換する。
- Tang Nano 20K用の`build/top.fs`をオープンソースFPGAツールで生成する。
- 実機へ転送するときはSRAM転送だけを使う。フラッシュ書き込みは行わない。

## Non-goals

- `/Users/valletta/dev/minios`の変更。
- SDRAM、HDMI、microSD、PMP、U-modeの実装。
- NESTangが入っているフラッシュの変更。
- macOS上のFTDIドライバを無効化する操作。

## Architecture

作業はこの独立クローン内で完結させる。FPGA側は既存のNEORV32、内蔵IMEM/DMEM、UART0、内蔵ブートローダー構成をそのまま使う。ソフトウェア側は依存クレートを持たない`no_std`/`no_main`のRustバイナリとし、UART0（`0xFFF50000`）を直接操作する。

FPGAツールはワークスペースローカルのOSS CAD Suiteを使い、Rust側は`riscv32imc-unknown-none-elf`を使う。実機転送がmacOSのUSBドライバに阻まれても、Rust実行ファイル、NEORV32実行形式、FPGAビットストリームの生成までは独立に完了できる。

## Success criteria

1. ホスト上のUART設定値テストが通る。
2. RV32IMC ELFに`_start`が存在する。
3. `neorv32_exe.bin`が生成される。
4. `build/top.fs`が生成される。
5. 実機転送を試す場合、`openFPGALoader`の`-f`オプションを使わない。

