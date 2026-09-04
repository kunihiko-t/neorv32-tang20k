#!/usr/bin/env bash
# ビルド→書き込み→実行→受信の一括フロー。フラッシュは触らない。
# 使い方: bash script/run_hello.sh [serial_port] [baud] [secs]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/script/env.sh"

PORT="${1:-/dev/cu.usbserial-20250303171}"
BAUD="${2:-19200}"
SECS="${3:-25}"

# CPUはRV32IM(C拡張なし)のためriscv32imでビルドする。imcだと即トラップする。
make -C "$ROOT/sw/minios_hello" build/minios_hello.elf TARGET=riscv32im-unknown-none-elf

PY="${PYTHON:-python3}"
if [ -z "${PYTHON:-}" ] && [ -x "$ROOT/.venv/bin/python" ]; then
  PY="$ROOT/.venv/bin/python"
fi

LOG="$ROOT/build/uart_hello.log"
mkdir -p "$ROOT/build"
"$PY" "$ROOT/script/uart_listen.py" "$PORT" "$BAUD" "$SECS" > "$LOG" 2>&1 &
LISTENER_PID=$!
sleep 2
timeout 40 openocd -f "$ROOT/script/ocd/run_hello.cfg"
wait "$LISTENER_PID"
cat "$LOG"
