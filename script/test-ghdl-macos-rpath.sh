#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tools_dir="${TANG_TOOLS_DIR:-$(dirname "$repo_root")/.tools}"
ghdl_bin="${OSS_CAD_SUITE:-$tools_dir/oss-cad-suite}/libexec/ghdl"
rpath_count=$(otool -l "$ghdl_bin" | awk '$1 == "path" && $2 == "@executable_path/../lib/" { count++ } END { print count + 0 }')

if [[ "$rpath_count" -ne 1 ]]; then
  echo "expected one OSS CAD Suite GHDL RPATH, found $rpath_count" >&2
  exit 1
fi

"$ghdl_bin" --version >/dev/null
