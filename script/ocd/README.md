# script/ocd の説明
- `target.cfg` / `interface.cfg` / `authentication.cfg` は
  NEORV32上流(`lib/neorv32/sw/openocd/`)と同等。ただし`target.cfg`の
  `gdb report_*` 2行は手元のHomebrew openocd 0.12.0が解釈できないため除去。
- `run_hello.cfg`: `reset halt`→IMEM書き込み→`pc=0`→実行→状態表示。
- `check_regs.cfg`: 読み取り専用の状態確認。
- 実機フローは`bash script/run_hello.sh`。
