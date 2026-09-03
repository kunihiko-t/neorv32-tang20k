#!/usr/bin/env bash

set -euo pipefail

app_dir=$(cd "$(dirname "$0")/.." && pwd)

make -C "$app_dir" image
make -C "$app_dir" app-vhd
strings "$app_dir/build/minios_hello.elf" | grep -qx _start
test -s "$app_dir/build/neorv32_exe.bin"

app_vhd="$app_dir/../../build/generated/neorv32_application_image.vhd"
raw_size=$(wc -c < "$app_dir/build/minios_hello.bin" | tr -d ' ')
grep -q "constant application_init_size_c  : natural := $raw_size;" "$app_vhd"
