# NEORV32 Tang Nano 20K MiniOS spike

Tang Nano 20K上でMiniOSを動かす前段階として、NEORV32とRV32IMC Rustプログラムのビルド経路を検証するプロジェクトです。

`/Users/valletta/dev/minios`には変更を加えていません。

## 現在できること

- NEORV32を96MHzでTang Nano 20K向けに合成する。
- `no_std`のRustプログラムをRV32IMC ELFへ変換する。
- RustプログラムをNEORV32ブートローダー用実行形式へ変換する。
- Tang Nano 20KのSRAMへ一時転送できるビットストリームを生成する。

RustプログラムはUART0へ`MiniOS/RV32 hello`と出力します。

## ビルド

最初にローカルツールチェーンを有効にします。

```sh
. script/env.sh
```

ツール環境とmacOS向け補正を確認します。

```sh
bash script/test-env.sh
bash script/test-ghdl-macos-rpath.sh
```

Rust側のテストとNEORV32実行形式の生成は次のコマンドで行います。

```sh
cargo test --manifest-path sw/minios_hello/Cargo.toml
bash sw/minios_hello/tests/check_image.sh
```

生成物は`sw/minios_hello/build/neorv32_exe.bin`です。

FPGAビットストリームはGNU make 4系で生成します。

```sh
gmake bitstream summary
```

生成物は`build/top.fs`です。

現在の構成は96MHz制約に対して最大105.52MHzで、LUT4を27.9%、BSRAMを56.5%使用します。

FPGA構成後にPLLがロックしてから、CPUを約5秒間リセットに保ちます。

これにより、JTAG転送終了後にUSB-UARTを開くための時間を確保します。

リセット回路の単体テストは次のコマンドで実行します。

```sh
gmake test-reset
```

## 実機確認の安全条件

まず次の読み取り専用コマンドで検出を確認します。

```sh
openFPGALoader --scan-usb
```

この環境では、SIPEED USB DebuggerとGowin GW2A(R)-18(C)を検出できています。

表示された場合だけ、次のコマンドでSRAMへ一時転送できます。

```sh
openFPGALoader -b tangnano20k build/top.fs
```

このコマンドはフラッシュを書き換えません。

電源を入れ直すと、フラッシュに保存されているNESTangへ戻ります。

`openFPGALoader`の`-f`オプションは使用しません。

NEORV32ブートローダーのUARTは19,200 baud、8-N-1です。

## UARTの現状

USBシリアルは`/dev/cu.usbserial-20250303171`として認識されていますが、現在はFPGAからのデータを受信できていません。

NEORV32とは独立した極小UART送信回路でも受信が0バイトだったため、NEORV32固有の問題よりもBL616、USB-UARTドライバ、または基板上の経路が有力です。

診断回路は次のコマンドで生成できます。

```sh
gmake uart-probe
```

生成物は`build/uart_probe/uart_probe.fs`です。

この回路はFPGAの69番ピンから115,200 baudで`0x55`を約100ミリ秒ごとに送信します。

ボード上のデバッガから識別子`2025030317`を取得しています。

[Sipeedの公式更新表](https://en.wiki.sipeed.com/hardware/en/tang/common-doc/update_debugger.html)でもTang Nano 20Kの現行版は`2025030317`とされているため、ファームウェアの再書込みは行っていません。

次の安全な確認手段は、外付けUSB-UARTまたはロジックアナライザで69番ピンの信号を直接測定することです。
