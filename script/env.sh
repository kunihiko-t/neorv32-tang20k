#!/usr/bin/env sh

export XDG_CONFIG_HOME=/Users/valletta/dev/tang_nano_20k/.tools/xdg/config
export XDG_CACHE_HOME=/Users/valletta/dev/tang_nano_20k/.tools/xdg/cache
export XDG_DATA_HOME=/Users/valletta/dev/tang_nano_20k/.tools/xdg/data

. /Users/valletta/dev/tang_nano_20k/.tools/oss-cad-suite/environment

rust_sysroot=$(rustc --print sysroot)
rust_host=$(rustc -vV | sed -n 's/^host: //p')
export PATH="/Users/valletta/dev/tang_nano_20k/neorv32-minios-spike/script/bin:$rust_sysroot/lib/rustlib/$rust_host/bin:$PATH"
unset rust_sysroot rust_host
