# HDMIシェル動作版の保存

2026年9月4日に、Tang Nano 20K上のMiniOS RV32シェルをUSB-UARTから操作し、HDMI画面への出力を確認しました。
以下はフラッシュ自動起動を追加する前の復旧点です。

## ソースと実行ファイル

| 対象 | 保存した版 |
| --- | --- |
| FPGA | `codex/neorv32-minios-spike` の `4984f8b` |
| MiniOS | `feature/neorv32-rv32-bringup` の `5282a92` |
| FPGAビットストリーム | `../checkpoints/2026-09-04-hdmi-sram/top.fs` |
| MiniOS ELF | `../checkpoints/2026-09-04-hdmi-sram/minios-kernel.elf` |

保存先はこのリポジトリーの`build/`の外側にあり、`gmake clean`では削除されません。
バイナリーはローカル保存のみで、Gitには含めていません。

SHA-256は次のとおりです。

```text
438750ebd1f787ba43a1ac19aac93e003862a5b1105d0e0f177e1f276d58c731  top.fs
68ba27cb7d1f431a19a32d52bdb4a2a91c030c41ed410fbd96595f2644832990  minios-kernel.elf
```

保存直前に`gmake test-console test-reset`、MiniOSの`cargo xtask check`全24段階、RV32リリースビルド、実機の`script/test_minios32_uart.py`が通りました。
既存のRV64/QEMU向けテストも維持しています。
MiniOS内の無関係な`.video_agent/`はコミットしていません。

## JTAGと復旧時の注意

この構成は`--jtag_as_gpio`によって、構成後のJTAGピンをNEORV32のCPUデバッグに使います。
`idcode 0x1`はCPU用TAPです。
FPGAの書き込み前には、Gowinの`idcode 0x81b`とIR長8を検出してください。
必要な場合はS2を押したままUSB-Cを挿し直し、FPGA構成用TAPへ戻します。
外部フラッシュ消去用の配線やデバッガのファームウェア更新は不要です。

`S1`はCPUを内部ブートローダーへ戻します。
RAMへ転送したMiniOSを実行するときは、CPUリセットではなく`script/ocd/reboot.cfg`の`reg pc 0; resume`を使います。
復旧用ビットストリームのSRAM転送には`-f`を付けません。

```sh
. script/env.sh
openFPGALoader -b tangnano20k --detect
# Gowin 0x81b / IR 8を確認した場合だけ実行する。
openFPGALoader -b tangnano20k ../checkpoints/2026-09-04-hdmi-sram/top.fs
```

FPGA再構成後にはMiniOSをRAMへ再転送する必要があります。
この時点のフラッシュにはHDMIなしの旧構成があり、今回のHDMI版はまだ保存していません。
自動起動の追加状況はREADMEの最新記録を参照してください。
