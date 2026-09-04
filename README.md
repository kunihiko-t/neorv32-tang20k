# NEORV32 on Tang Nano 20K

Tang Nano 20KでRISC-Vプロセッサー「NEORV32」とRustプログラムを動かすプロジェクトです。
MiniOSのRV32移植に向けたFPGA構成と、ビルドやデバッグ用のスクリプトを含みます。
[jpf91/neorv32-tang20k](https://github.com/jpf91/neorv32-tang20k)をベースにしています。

## 対応範囲

- NEORV32 RV32IM、96 MHz。圧縮命令（C拡張）は無効。
- Rustの`no_std`プログラムをRV32実行形式へビルド。
- USB-JTAGでFPGAのSRAMへ一時転送。
- USB-UARTへ文字列を出力する`minios_hello`デモ。

MiniOS本体はこのリポジトリに含みません。
MiniOS向けのRAM転送補助は`script/run_minios32.sh`、OpenOCDの設定は[デバッグ手順](script/ocd/README.md)を参照してください。
HDMI、SDカード、USBキーボードの直接接続は、この公開版には未実装です。

## 必要なもの

- Tang Nano 20K、データ通信対応のUSB-Cケーブル。
- macOS、Rust、Python 3、GNU make 4系、Cコンパイラー。
- OSS CAD Suite（Yosys、GHDL、nextpnr-himbaechel、apycula）、openFPGALoader、OpenOCD。

RustのターゲットとLLVMツール、Pythonのシリアル通信ライブラリーを用意します。

```sh
rustup target add riscv32im-unknown-none-elf
rustup component add llvm-tools-preview
python3 -m venv .venv
. .venv/bin/activate
python -m pip install pyserial
git submodule update --init --recursive
```

以下のコマンドはリポジトリのルートで実行します。

## ビルド

OSS CAD Suiteは`../.tools/oss-cad-suite`に配置します。
別の場所を使う場合は`OSS_CAD_SUITE`にインストール先を指定してください。
XDG設定とキャッシュの保存先は`../.tools/xdg`です。`TANG_TOOLS_DIR`で`.tools`の位置を変更できます。

BashまたはZshで環境を読み込み、ビルドします。

```sh
. script/env.sh
bash script/test-env.sh
cargo test --manifest-path sw/minios_hello/Cargo.toml
bash sw/minios_hello/tests/check_image.sh
gmake bitstream summary
```

FPGAの生成物は`build/top.fs`です。
デモの実行形式は`sw/minios_hello/build/neorv32_exe.bin`です。

macOSでGHDLが起動しない場合は、`bash script/test-ghdl-macos-rpath.sh`で確認してください。
重複RPATHへの補正は`script/fix-ghdl-macos-rpath.sh`、nextpnrのXDG設定への補正は`script/fix-nextpnr-macos-paths.sh`で行えます。

## FPGAへ一時転送する

端末を閉じ、S2を押したままUSB-Cを接続してからS2を離します。
構成用JTAGでGowinが検出できることを確認します。

```sh
openFPGALoader -b tangnano20k --detect
```

`Gowin GW2A(R)-18(C)`が表示された場合だけ、次を実行します。

```sh
openFPGALoader -b tangnano20k build/top.fs
```

これはSRAMへの一時転送です。フラッシュは変更しません。
電源を切るとフラッシュに保存した構成へ戻ります。
`-f`はフラッシュを書き換えるため、一時転送には付けないでください。

この設計では`--jtag_as_gpio`を使い、動作中のJTAGピンをNEORV32のCPUデバッグに切り替えます。
動作中の`idcode 0x1`を、FPGA構成用JTAGの検出成功と解釈しないでください。
S1はCPUリセット、S2を押したままの電源投入はFPGA構成用JTAGへ戻る操作です。

## Rustデモを実行する

FPGAの構成後、CPUの起動を待ってからポート名を確認します。
以下の`PORT`を使用するボードのポートに置き換えてください。

```sh
.venv/bin/python -m serial.tools.list_ports
export PORT=/dev/cu.usbserial-XXXXXXXX
bash script/run_hello.sh "$PORT" 19200 25
```

デモはRAMへ転送され、UARTに`MiniOS/RV32 hello`を出力します。
実行スクリプトは`.venv/bin/python`を優先します。別のPythonを使う場合は`PYTHON`で指定してください。
フラッシュは書き換えません。
UARTは19,200 baud、8-N-1です。
転送やテストの前には端末を閉じ、同じポートを同時に開かないでください。

MiniOSを別途用意する場合、`MINIOS`にチェックアウト先を指定できます。
省略時の配置は、このリポジトリから見て`../../minios`です。
