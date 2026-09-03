# 作業メモ: NEORV32上でRust製helloを実行する(2026-09-03更新)

以前のロジックアナライザ切り分け記録は-historyとして残すが、
2026-09-03にOpenOCD経由の実行フローが確立したため、現行手順は本書を正とする。

## 確立した事実

- `MiniOS/RV32 hello` (19 bytes) をUART受信済み。複数回再現。
- LEDはUSB-C側から `消灯・点灯・点滅・消灯・点灯・消灯` が正。
  前3つはリセット・PLL・クロック点滅、後3つはGPIO `0b101` の負論理表示。
- CPUはRV32IM(C拡張なし)。`misa=0x40801100` で確認。
  ファームは必ず `TARGET=riscv32im-unknown-none-elf` でビルドする。imcは即トラップする。
- フラッシュ(9/1書き込み)のNEORV32が通常起動すればJTAGは生きている。
  `openFPGALoader --scan-usb` でSIPEED `2025030317` を確認する。
- 既にhelloが走って`wfi`待機中だと`load_image`がbusy失敗する。
  必ず`reset halt`してから書き込む(`script/ocd/run_hello.cfg`済み)。
- `S1`(左ボタン)=CPUリセット。`S2`+電源投入はフラッシュ起動を止めて
  FPGAが空(JTAGブート待ち・LED全消灯)になるため、通常は使わない。
  JTAGが`IDCODE 0x1`/`DTM version 15`で失敗したら、まず何も押さず挿し直して8秒待つ。
- OSSフロー(`gowin_pack`/`nextpnr-himbaechel`)はBRAM初期化データを落とすため、
  ビットストリーム内蔵IMEM起動(`BOOT_MODE_SELECT=2`+`app-vhd`)は使わない。
  実行時はOpenOCDの`load_image`でIMEMへ直接書く。
- macOSのCDCは`stty`設定がfd closeで消える。受信は`pyserial`を同一fdで使う
  (`script/uart_listen.py`+`../tools/bl616/venv`)。

## 現行フロー

```sh
source script/env.sh
bash script/run_hello.sh
```

中身: `riscv32im`で`build/minios_hello.elf`をビルド→リスナー起動→
`openocd -f script/ocd/run_hello.cfg`(reset halt→load→pc=0→resume)→受信表示。
ログは`build/uart_hello.log`。読み取り専用確認は`openocd -f script/ocd/check_regs.cfg`。

## 過去の切り分け記録(2026-09-02までの経緯)

- 69番ピン経由のUSB-UARTで受信0。極小UART送信回路でも0だった。
- 診断回路(`diagnostics/uart_probe`)を71番へ迂回し、sigrok(`fx2lafw`)で取得。
  アナライザ自体はGND直結で全Lowを確認し正常と確定(CH1=D0対応)。
  しかし71番は300ms・600,000サンプル全High、UART復号0件で`0x55`未観測。
  接触・位置・FPGA出力のいずれかが残課題だが、OpenOCD経路の確立により優先度を下げた。
  診断イメージSHA-256: `3857e7b5...775cf` (`build/uart_probe/uart_probe.fs`)。

## 未コミット差分の扱い(提案)

- `src/hdl/top.vhd`の`BOOT_MODE_SELECT=2`は現フローでは不要(フラッシュ=0のまま使う)。
  戻すか残すか決めること。
- `sw/minios_hello`のGPIO表示・`norvc`・`app-vhd`まわりはhello動作に寄与。
  ただし`app-vhd`+`BOOT_MODE_SELECT=2`の自己ブート経路はBRAM欠落で動かないため、
  ドキュメントにその旨を明記すること。
- `diagnostics/uart_probe`の71番変更は診断用に残してよい。

## 残課題

- BRAM INIT欠落をapycula/`nextpnr-himbaechel`へ報告。
- `top.vhd`に`RISCV_ISA_C => true`を足すFPGA再ビルド案(要JTAG影響の再確認)。
- 本書の手順で`cargo test`/`check_image.sh`相当の受け入れを更新する。
- ユーザー許可なく`openFPGALoader -f`でフラッシュを書き換えない。
- `restore`/`reset`/`clean`/stashは差分確認まで実行しない。
