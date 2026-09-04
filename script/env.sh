#!/usr/bin/env bash
# Source from Bash or Zsh; locations are relative to this checkout.

if [ -n "${BASH_VERSION:-}" ]; then
  tang_env_file="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  tang_env_file="${(%):-%x}"
else
  echo "Source script/env.sh from Bash or Zsh." >&2
  return 1
fi
tang_repo_root=$(cd "$(dirname "$tang_env_file")/.." && pwd)
tang_tools_dir="${TANG_TOOLS_DIR:-$(dirname "$tang_repo_root")/.tools}"
tang_suite="${OSS_CAD_SUITE:-$tang_tools_dir/oss-cad-suite}"
if [ ! -f "$tang_suite/environment" ]; then
  echo "OSS CAD Suite not found; set OSS_CAD_SUITE to its installation directory." >&2
  return 1
fi

export XDG_CONFIG_HOME="$tang_tools_dir/xdg/config"
export XDG_CACHE_HOME="$tang_tools_dir/xdg/cache"
export XDG_DATA_HOME="$tang_tools_dir/xdg/data"

. "$tang_suite/environment"

rust_sysroot=$(rustc --print sysroot)
rust_host=$(rustc -vV | sed -n 's/^host: //p')
export PATH="$tang_repo_root/script/bin:$rust_sysroot/lib/rustlib/$rust_host/bin:$PATH"
unset rust_sysroot rust_host tang_env_file tang_repo_root tang_tools_dir tang_suite
