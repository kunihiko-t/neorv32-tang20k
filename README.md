# NEORV32 Tang Nano 20K MiniOS spike

Tang Nano 20K上のNEORV32で、RV32IM版MiniOSを動かすプロジェクトです。

MiniOS側は`/Users/valletta/dev/minios`の`feature/neorv32-rv32-bringup`ブランチを使います。
RV64/QEMU版は別のターゲットとして維持します。

## 現在できること

- NEORV32を96MHzでTang Nano 20K向けに合成する。
- `no_std`のRustプログラムをRV32IM ELFへ変換する。
- RustプログラムをNEORV32ブートローダー用実行形式へ変換する。
- Tang Nano 20KのSRAMへ一時転送できるビットストリームを生成する。
- MiniOS RV32をRAMへ転送し、MacからUSB-UARTで`help`、`info`、`echo`を操作する。
- MiniOSのUART出力をHDMI画面へ複写する（SRAM版で実機確認済み）。

単体デモの`sw/minios_hello`はUART0へ`MiniOS/RV32 hello`と出力します。
MiniOSカーネルのシェルを使う手順は、末尾の「MacのキーボードでMiniOSを操作する」を参照してください。

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

HDMIを追加した構成は、CPUの96MHz制約に対して最大102.97MHzです。
映像の27MHz制約も満たし、LUT4を29.8%、BSRAMを60.9%、PLLを2個中2個使用します。
これらの数値は配置配線後の計算結果です。
HDMIへの文字表示は、2026年9月4日に実機で確認しました。

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
openFPGALoader -b tangnano20k --detect
```

USBデバッガの検出だけでは、FPGA構成用JTAGにアクセスできるかは判断できません。
`--detect`でGowin GW2A(R)-18(C)を確認します。
`idcode 0x1`は、この設計ではNEORV32のCPUデバッグ用TAPであり、FPGAの書き込み準備完了を意味しません。
CPU用TAPが見えている場合は、S2を押したまま電源を入れ直してFPGA構成用TAPを再検出します。

Gowinを検出できた場合だけ、次のコマンドでSRAMへ一時転送できます。

```sh
openFPGALoader -b tangnano20k build/top.fs
```

このコマンドはフラッシュを書き換えません。

2026年9月1日に、`build/top.fs`を外部フラッシュの先頭へ検証付きで書き込みました。

現在は電源を入れ直してもNEORV32が起動します。

以前保存されていたNESTangは上書きされています。

通常の開発ではSRAM転送を使います。

外部フラッシュを更新するときだけ、対象を再検出してから`-f --verify`を使用します。

NEORV32ブートローダーのUARTは19,200 baud、8-N-1です。

## 実行フロー(OpenOCD経由、2026-09-03確立)

フラッシュのNEORV32を通常起動(S2なしでUSB挿入、8秒待機)し、次のコマンドで実行します。

```sh
. script/env.sh
bash script/run_hello.sh
```

CPUはRV32IM(C拡張なし)のため、`riscv32im-unknown-none-elf`でビルドします。
既にプログラムが走って`wfi`待機中だと書き込みがbusy失敗するため、
`script/ocd/run_hello.cfg`は`reset halt`してからIMEMへ直接書き込み、
`pc=0`から実行します。ログは`build/uart_hello.log`です。

期待値はUARTへの`MiniOS/RV32 hello`と、USB-C側からのLED
`消灯・点灯・点滅・消灯・点灯・消灯`(GPIO `0b101`の負論理表示)です。

`S1`はCPUリセットです。`S2`+電源投入はFPGAが空になるため通常は使いません。

## UARTの診断記録

以下はUARTが受信できなかった時点の記録です。
現在は`/dev/cu.usbserial-20250303171`でMiniOSの起動ログとシェルのコマンド応答を受信確認済みです。

NEORV32とは独立した極小UART送信回路でも受信が0バイトだったため、NEORV32固有の問題よりもBL616、USB-UARTドライバ、または基板上の経路が有力です。

診断回路は次のコマンドで生成できます。

```sh
gmake uart-probe
```

生成物は`build/uart_probe/uart_probe.fs`です。

この回路はFPGAの69番ピンから115,200 baudで`0x55`を約100ミリ秒ごとに送信します。

ボード上のデバッガから識別子`2025030317`を取得しています。

[Sipeedの公式更新表](https://en.wiki.sipeed.com/hardware/en/tang/common-doc/update_debugger.html)でもTang Nano 20Kの現行版は`2025030317`とされているため、ファームウェアの再書込みは行っていません。

## MacのキーボードでMiniOSを操作する

USB-C経由のUARTを使うため、FPGAにキーボードを直接接続する必要はありません。
まずNEORV32が通常起動した状態で、MiniOSをRAMへ転送します。
以下はすべてこのリポジトリーのルートで実行します。

```sh
. script/env.sh
bash script/run_minios32.sh /dev/cu.usbserial-20250303171 19200 10
```

転送が終わったら、インストール済みのpyserialで端末を開きます。

```sh
../tools/bl616/venv/bin/python -m serial.tools.miniterm --eol CR /dev/cu.usbserial-20250303171 19200
```

Enterを押すと`minios> `が表示されます。
`help`、`info`、`echo hello from Mac`を入力できます。
Backspaceで末尾の文字を消せます。
入力は半角英数字などの印字可能なASCIIで、1行128バイトまでです。
応答中に次のコマンドを送らず、`minios> `が戻ってから1行ずつ入力してください。
現状のUARTは受信FIFOが1バイトで、実機では長文の一括送信による取りこぼしを確認しています。
自動テストでは1文字ずつ間隔を空けて送信します。
端末を閉じるときは`Ctrl+]`を押します。
転送や自動テストの前には端末を閉じて、シリアルポートの同時使用を避けてください。

実行中のMiniOSにコマンドを送って検証するには、次を使います。

```sh
../tools/bl616/venv/bin/python script/test_minios32_uart.py
```

これらのコマンドはフラッシュを書き換えません。
電源の入れ直しやS1によるリセット後は、MiniOSをRAMへ再転送してください。
フラッシュに保存済みの旧構成にはHDMIシェル表示がありません。
以下の新構成をSRAMへ転送した場合だけ、HDMIへの複写が有効になります。

## UART出力をHDMIへ複写する構成

CPUのUART送信をFPGA内部でも受信し、64列30行の文字バッファへ書き込みます。
MiniOSの出力先や入力処理は変更しません。
画面は既存の720×480、60Hzの映像回路を使い、8×16ピクセルの文字を中央に表示します。
印字可能ASCII、CR、LF、Backspace、行折り返しとスクロールに対応し、ANSIエスケープシーケンスや日本語には対応していません。

元の`build/top.fs`を保ったまま、新構成だけを生成する手順です。

```sh
. script/env.sh
gmake test-console
gmake OBJDIR=build/hdmi_minios bitstream summary
```

生成物は`build/hdmi_minios/top.fs`です。
単体テスト、UART受信と端末バッファの接続テスト、毎クロック変化する画素の同期検査、合成、配置配線、ビットストリーム生成が通っています。
2026年9月4日にこの構成をSRAMへ転送し、NEORV32の起動ログをUARTで受信しました。
MiniOSの5,514語は1回目の転送で`unmatched=0`となり、コマンド、Backspace、入力長制限、復帰、CRLFの実機UARTテストも通りました。
最後に`echo HDMI MIRROR READY`を実行しています。
ユーザーの目視で、HDMIモニターに`echo HDMI MIRROR READY`などの出力と、最下行の`minios>`が表示されることを確認しました。
使用したビットストリームのSHA-256は`438750ebd1f787ba43a1ac19aac93e003862a5b1105d0e0f177e1f276d58c731`です。
フラッシュは変更していません。

搭載ツールのapyculaには、GW2Aの左側PLLを処理すると`offx`が未初期化になる不具合があります。
CPUと映像で左右両方のPLLを使うため、`script/pack_gowin.py`がその場合だけ座標計算を補正します。
インストール済みライブラリーは変更せず、補正済みツールでは処理を置き換えません。
左右のPLL座標と補正の再実行は`gmake test-console`で検証します。

実機では上の安全条件でGowinを検出してから、次を実行します。

```sh
openFPGALoader -b tangnano20k build/hdmi_minios/top.fs
# CPU起動を待ち、NEORV32のデバッグ用TAPに切り替わったことを確認する。
bash script/run_minios32.sh /dev/cu.usbserial-20250303171 19200 10
```

FPGAを再構成するとMiniOSのRAM内容も失われるため、再転送が必要です。
`PACK_FLAGS=--jtag_as_gpio`はCPUデバッグ用TAPに接続するために維持しています。
新構成をフラッシュへ書き込む手順ではありません。
電源を入れ直すとフラッシュ内のHDMIなし構成へ戻ります。

Muse SparkとLunaの担当範囲、時間、品質の記録は[実装比較](docs/2026-09-04-muse-luna-evaluation.md)を参照してください。

## フラッシュ自動起動の準備

HDMIシェル動作版のソースと実行ファイルは、[復旧点の記録](docs/2026-09-04-hdmi-checkpoint.md)に保存しています。
以下はMiniOS本体の起動イメージを作成する手順であり、フラッシュは書き換えません。
`sw/minios_hello`とは別のプログラムです。

```sh
. script/env.sh
cargo build --release -p minios-kernel --bin minios-kernel \
  --target riscv32im-unknown-none-elf --locked \
  --manifest-path /Users/valletta/dev/minios/Cargo.toml
python3 -m unittest discover -s test -p test_minios32_image.py
python3 script/build_minios32_image.py
```

生成物は`build/minios32/neorv32_exe.bin`です。
別のチェックアウトを使う場合は、ビルド時の`--manifest-path`と生成時の`--minios`を同じMiniOSへ向けてください。
生成処理はコンパイル済みのELFを使用し、メモリー範囲を検査した後に、同梱のNEORV32 `image_gen`でヘッダーを付けます。
出力前にサイズとチェックサムを検証します。

NEORV32のブートローダーは、フラッシュの`0x400000`から実行形式を読み、ペイロードをIMEMの先頭へ配置します。
`.data`の初期値もIMEMに格納し、RV32起動コードがDMEMへコピーします。
`script/ocd/gen_mww_load.py`も同じロードアドレス（LMA）へ書き込むため、JTAG経由のRAM起動と配置が一致します。

| 保存対象 | フラッシュ内の開始位置 | 準備したファイル |
| --- | --- | --- |
| HDMI対応FPGA回路 | `0x000000` | `build/hdmi_minios/top.fs` |
| MiniOS実行形式 | `0x400000` | `build/minios32/neorv32_exe.bin` |

書き込み前にはGowinの構成用TAPを再検出し、対象フラッシュの容量を確認して既存内容をバックアップします。
書き込みは領域ごとに`--verify`を付けて行い、最後に通常の電源投入で起動を確認します。
この準備段階では、フラッシュ自動起動はまだ実機確認していません。

2026年9月4日の候補は22,116バイト（ヘッダー12バイト、ペイロード22,104バイト）です。
SHA-256は`8842da45e095cc35eba7e3ca90605978acb880d92124dfecf54f9a2b898c6891`です。
MiniOSの起動処理修正は`6f49b7b`に保存しています。
このELFの`.data`はLMA `0x5654`、VMA `0x80000000`、初期値`0xffffffff`の4バイトです。
実機でVMAをゼロにして起動コードを実行する検査では、修正前はゼロのまま、修正後は初期値へのコピーを3回の読み戻しで確認しました。
起動イメージのペイロードは、独立した`rust-objcopy -O binary`の出力とも完全一致しました。
候補のELFと実行形式は、`../checkpoints/2026-09-04-flash-candidate/`にも保存しています。

### USB-UARTのバイナリー転送制限

標準BL616ファームウェアは、`Ctrl+X`に続く`Ctrl+C`でFPGAのUARTから管理端末へ切り替わります。
これは[Sipeedの公式手順](https://en.wiki.sipeed.com/hardware/en/tang/tang-nano-20k/example/unbox.html#choose)に記載された操作です。
今回の実行イメージにも同じバイト列が含まれ、ブートローダーへのUART転送中に`TangNano20K />`へ切り替わることを確認しました。
そのため、バイナリーの転送にはJTAGを使います。
管理端末へ入った場合は`choose uart`で通常の接続へ戻せます。
半角文字によるMiniOSシェルの操作は引き続きUSB-UARTを使用します。
