# script/ocd の説明
- `target.cfg` / `interface.cfg` / `authentication.cfg` は
  NEORV32上流(`lib/neorv32/sw/openocd/`)と同等。ただし`target.cfg`の
  `gdb report_*` 2行は手元のHomebrew openocd 0.12.0が解釈できないため除去。
- `run_hello.cfg`: `reset halt`→IMEM書き込み→`pc=0`→実行→状態表示。
- `check_regs.cfg`: 読み取り専用の状態確認。
- 実機フローは`bash script/run_hello.sh`。
- `run_bin.cfg` + `gen_mww_load.py` + `script/run_minios32.sh`:
  MiniOS RV32カーネル用。`load_image`のprogram-buffer経路が
  `abstractcs=0x02000b01`(cmderr=busy固着)で不安定なため、
  ELFのLOADを`mww`で1語ずつ書く。固着時は`dmi_write 0x16 0x700`で解除し、
  読み戻し検証で不一致だけ最大8回書き直す。複数回走らせると収束する。
  検証後は`reboot.cfg`の`reg pc 0; resume`で転送済みプログラムを実行する。
  `reset run`は内部ブートローダーへ戻るため、MiniOSの転送後には使わない。
