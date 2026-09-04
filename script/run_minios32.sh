#!/usr/bin/env bash
# MiniOS RV32カーネルをビルドし、mww経路でNEORV32へ書き込んで実行する。フラッシュは触らない。
# 使い方: bash script/run_minios32.sh [serial_port] [baud] [secs]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MINIOS="${MINIOS:-/Users/valletta/dev/minios}"
PORT="${1:-/dev/cu.usbserial-20250303171}"
BAUD="${2:-19200}"
SECS="${3:-30}"

cargo build --release -p minios-kernel --bin minios-kernel \
  --target riscv32im-unknown-none-elf --manifest-path "$MINIOS/Cargo.toml"
ELF="$MINIOS/target/riscv32im-unknown-none-elf/release/minios-kernel"
WORDS="$ROOT/build/mww_words.cfg"
mkdir -p "$ROOT/build"
python3 "$ROOT/script/ocd/gen_mww_load.py" "$ELF" "$WORDS"

VENV_PY="$ROOT/../tools/bl616/venv/bin/python"
if [ -x "$VENV_PY" ]; then
  PY="$VENV_PY"
else
  PY="python3"
fi

OCDLOG="$ROOT/build/openocd_minios32.log"
LOG="$ROOT/build/uart_minios32.log"
# DMIが散発的に失敗するため、全語一致まで最大4回繰り返す。
# 検証と実行を分ける。検証は時間がかかるため、受信待機は実行直前に始める。
for attempt in 1 2 3 4; do
  echo "=== attempt $attempt ==="
  MWW_WORDS="$WORDS" timeout 400 openocd -f "$ROOT/script/ocd/run_bin.cfg" > "$OCDLOG" 2>&1 || true
  grep -E "unmatched=|FAILED" "$OCDLOG" | tail -n 5
  if grep -q "unmatched=0" "$OCDLOG"; then
    "$PY" "$ROOT/script/uart_listen.py" "$PORT" "$BAUD" "$SECS" > "$LOG" 2>&1 &
    LISTENER_PID=$!
    sleep 2
    timeout 30 openocd -f "$ROOT/script/ocd/reboot.cfg" > /dev/null 2>&1 || true
    wait "$LISTENER_PID" || true
    cat "$LOG"
    grep -Fq "MiniOS/RV32 booting..." "$LOG"
    exit $?
  fi
done
exit 1
