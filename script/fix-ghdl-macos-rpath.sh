#!/usr/bin/env bash

set -euo pipefail

ghdl_bin=/Users/valletta/dev/tang_nano_20k/.tools/oss-cad-suite/libexec/ghdl
rpath='@executable_path/../lib/'
rpath_count=$(otool -l "$ghdl_bin" | awk -v wanted="$rpath" '$1 == "path" && $2 == wanted { count++ } END { print count + 0 }')

if [[ "$rpath_count" -lt 1 ]]; then
  echo "OSS CAD Suite GHDL has no expected RPATH" >&2
  exit 1
fi

while [[ "$rpath_count" -gt 1 ]]; do
  install_name_tool -delete_rpath "$rpath" "$ghdl_bin"
  rpath_count=$((rpath_count - 1))
done

codesign --force --sign - "$ghdl_bin"
