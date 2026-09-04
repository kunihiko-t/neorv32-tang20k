#!/bin/bash

# Optional compiler installation; otherwise use the caller's PATH.
if ! command -v riscv-none-elf-gcc >/dev/null 2>&1 && [ -n "${RISCV_TOOLCHAIN:-}" ]; then
    export PATH="$PATH:$RISCV_TOOLCHAIN/bin"
fi

# Allow sourcing this script without params. Otherwise exec command
if [ $# -ne 0 ]; then
    exec "$@"
fi
