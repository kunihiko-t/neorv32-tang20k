#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tools_dir="${TANG_TOOLS_DIR:-$(dirname "$repo_root")/.tools}"
wrapper="${OSS_CAD_SUITE:-$tools_dir/oss-cad-suite}/bin/nextpnr-himbaechel"

sed -i '' 's|export XDG_CONFIG_HOME=$HOME/.config/yosyshq|export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config/yosyshq}"|g' "$wrapper"
sed -i '' 's|export XDG_CACHE_HOME=$HOME/.cache/yosyshq|export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache/yosyshq}"|g' "$wrapper"
sed -i '' 's|export XDG_DATA_HOME=$HOME/.local/share/yosyshq|export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share/yosyshq}"|g' "$wrapper"
sed -i '' 's|mkdir -p $HOME/.config/yosyshq $HOME/.local/share/yosyshq|mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"|g' "$wrapper"
