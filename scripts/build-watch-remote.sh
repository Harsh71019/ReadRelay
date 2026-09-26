#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
venv_dir="$project_root/.venv"

if [[ ! -x "$venv_dir/bin/pio" ]]; then
  python3 -m venv "$venv_dir"
  "$venv_dir/bin/pip" install --upgrade \
    https://github.com/pioarduino/platformio-core/archive/refs/tags/v6.1.19.zip
fi

cd "$project_root"
"$venv_dir/bin/pio" run -e default

mkdir -p "$project_root/dist"
cp "$project_root/.pio/build/default/firmware.bin" \
  "$project_root/dist/x4-watch-turner-firmware.bin"

printf 'Firmware: %s\n' "$project_root/dist/x4-watch-turner-firmware.bin"
shasum -a 256 "$project_root/dist/x4-watch-turner-firmware.bin"
