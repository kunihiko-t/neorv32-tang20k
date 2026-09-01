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

現在の構成は96MHz制約に対して最大104.25MHzで、LUT4を27.9%、BSRAMを56.5%使用します。

## 実機確認の安全条件

現在のmacOS環境では、AppleUSBFTDIドライバがJTAGインターフェースを使用しており、`openFPGALoader`から基板を検出できません。

まず次の読み取り専用コマンドで検出を確認します。

```sh
openFPGALoader --scan-usb
```

Tang Nano 20Kが表示されない場合は、そこで停止します。

表示された場合だけ、次のコマンドでSRAMへ一時転送できます。

```sh
openFPGALoader -b tangnano20k build/top.fs
```

このコマンドはフラッシュを書き換えません。

電源を入れ直すと、フラッシュに保存されているNESTangへ戻ります。

`openFPGALoader`の`-f`オプションは使用しません。

NEORV32ブートローダーのUARTは19,200 baud、8-N-1です。
