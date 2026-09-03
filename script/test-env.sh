#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/env.sh"

test "$XDG_CONFIG_HOME" = /Users/valletta/dev/tang_nano_20k/.tools/xdg/config
test "$XDG_CACHE_HOME" = /Users/valletta/dev/tang_nano_20k/.tools/xdg/cache
test "$XDG_DATA_HOME" = /Users/valletta/dev/tang_nano_20k/.tools/xdg/data

mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
test -w "$XDG_CONFIG_HOME"
test -w "$XDG_CACHE_HOME"
test -w "$XDG_DATA_HOME"

for tool in yosys ghdl nextpnr-himbaechel gowin_pack rust-objcopy; do
  command -v "$tool" >/dev/null
done

rust-objcopy --version >/dev/null

nextpnr_output=$(nextpnr-himbaechel --version 2>&1)
if [[ "$nextpnr_output" == *"Operation not permitted"* ]]; then
  echo "$nextpnr_output" >&2
  exit 1
fi
