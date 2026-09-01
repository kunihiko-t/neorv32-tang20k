#!/usr/bin/env bash

set -euo pipefail

app_dir=$(cd "$(dirname "$0")/.." && pwd)

make -C "$app_dir" image
strings "$app_dir/build/minios_hello.elf" | grep -qx _start
test -s "$app_dir/build/neorv32_exe.bin"
