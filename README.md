# MiniOS on Tang Nano 20K

Tang Nano 20KのFPGAにRISC-Vプロセッサー「NEORV32」を構成し、Rust製MiniOSを動かすプロジェクトです。
[jpf91/neorv32-tang20k](https://github.com/jpf91/neorv32-tang20k)をベースにしています。

## 対応機能

- NEORV32 RV32IM、96 MHz。圧縮命令（C拡張）は無効。
- USB-UART経由でMacから操作するMiniOSの小型シェル。
- `help`、`info`、`echo`、Backspaceによる行編集。
- UART出力をHDMIへ表示する64列×30行のテキスト画面。
- FPGA回路とMiniOSをフラッシュに保存した構成での自動起動。

MiniOS本体は別リポジトリの`feature/neorv32-rv32-bringup`ブランチを使います。
RV64/QEMU版の全機能を移植したものではありません。
MiniOSからのSDファイルシステム利用とUSBキーボードの直接接続は未対応です。
SDカードには独立した読み取り専用診断があります。

## 必要なもの

- Tang Nano 20K、データ通信対応のUSB-Cケーブル。
- HDMI入力のあるモニター（画面表示を使う場合）。
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
同梱の単体デモは`sw/minios_hello/build/neorv32_exe.bin`に生成され、UARTへ`MiniOS/RV32 hello`を出力します。
このデモとMiniOSカーネルは別のプログラムです。

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

## MiniOSを起動して操作する

MiniOSのRV32ブランチを別途用意し、`MINIOS`にチェックアウト先を指定します。
省略時は`../../minios`を使います。
シリアルポート名を確認し、以下の`PORT`には使用するボードのポートを設定してください。

```sh
.venv/bin/python -m serial.tools.list_ports
export PORT=/dev/cu.usbserial-XXXXXXXX
export MINIOS=../../minios
bash script/run_minios32.sh "$PORT" 19200 10
.venv/bin/python -m serial.tools.miniterm --eol CR "$PORT" 19200
```

Enterを押すと`minios>`が表示されます。
`help`、`info`、`echo hello`を試してください。
終了は`Ctrl+]`です。
実行スクリプトは`.venv/bin/python`を優先します。別のPythonを使う場合は`PYTHON`で指定してください。

入力は印字可能なASCIIで、1行128バイトまでです。
UARTは19,200 baud、8-N-1で、受信バッファが小さいため、長文の一括貼り付けは避けてください。
コマンドはプロンプトが戻ってから1行ずつ入力します。
転送やテストの前には端末を閉じ、同じポートを同時に開かないでください。

フラッシュにMiniOSまで保存済みなら、通常の電源投入後に30秒ほど待って端末を開くだけで操作できます。
S2操作やRAMへの再転送は不要です。

## HDMIと開発用テスト

HDMIにはUART出力と同じ文字を表示します。
映像は720×480、60 Hzで、ASCII、改行、行折り返し、スクロールに対応します。
日本語とANSIエスケープシーケンスには未対応です。

```sh
gmake test-reset test-console
tabbypy3 -m unittest discover -s test
```

MiniOSのSPI起動イメージは、RV32カーネルをビルドしてから`python3 script/build_minios32_image.py`で生成します。
FPGA回路はフラッシュ先頭、MiniOS実行形式は`0x400000`に置く構成です。
フラッシュ更新は一時転送の動作確認後に、バックアップと読み戻し検証を伴う別作業として行ってください。

OpenOCDによるRAM転送の仕組みは[デバッグ手順](script/ocd/README.md)を参照してください。
内蔵microSDスロットの読み取り専用診断は[SDプローブ手順](diagnostics/sd_probe/README.md)を参照してください。
これはMiniOSのファイルシステム機能ではなく、ブロック0を検証する独立した診断プログラムです。
