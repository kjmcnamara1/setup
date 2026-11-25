#!/usr/bin/env bash
# RetroArch launcher used by ES-DE (es_systems.xml).
#   bee-ra.sh <system> <core>[,<core>...] <rom>
# Picks the first core that exists (Batocera's preferred core first, packaged
# fallback after), and points saves/states at the synced Batocera-style folder
# ~/Nextcloud/Games/bee/saves/<system> and BIOS at ~/Games/bios/<system>.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: bee-ra.sh <system> <core>[,<core>...] <rom>" >&2
  exit 64
fi
system="$1" cores="$2" rom="$3"

BEE_RA_BIN="${BEE_RA_BIN:-retroarch}"
BEE_RA_CORE_DIRS="${BEE_RA_CORE_DIRS:-$HOME/.config/retroarch/cores:/usr/lib/libretro}"
# Batocera-style exit: hold Select (hotkey) + press Start. Button numbers are for
# Xbox-layout pads on Linux (Back=6, Start=7); override if your pad differs.
BEE_RA_HOTKEY_BTN="${BEE_RA_HOTKEY_BTN:-6}"
BEE_RA_EXIT_BTN="${BEE_RA_EXIT_BTN:-7}"

core_path=""
IFS=',' read -r -a wanted <<<"$cores"
IFS=':' read -r -a dirs <<<"$BEE_RA_CORE_DIRS"
for c in "${wanted[@]}"; do
  for d in "${dirs[@]}"; do
    if [[ -f "$d/${c}_libretro.so" ]]; then core_path="$d/${c}_libretro.so"; break 2; fi
  done
done
if [[ -z "$core_path" ]]; then
  echo "bee-ra: none of the cores '$cores' found in $BEE_RA_CORE_DIRS" >&2
  exit 2
fi

saves="$HOME/Nextcloud/Games/bee/saves/$system"
bios="$HOME/Games/bios/$system"
mkdir -p "$saves"
cfg="${XDG_RUNTIME_DIR:-/tmp}/bee-ra-$system.cfg"
cat >"$cfg" <<EOF
savefile_directory = "$saves"
savestate_directory = "$saves"
system_directory = "$bios"
sort_savefiles_enable = "false"
sort_savestates_enable = "false"
sort_savefiles_by_content_enable = "false"
sort_savestates_by_content_enable = "false"
input_enable_hotkey_btn = "$BEE_RA_HOTKEY_BTN"
input_exit_emulator_btn = "$BEE_RA_EXIT_BTN"
EOF

exec "$BEE_RA_BIN" -L "$core_path" --appendconfig "$cfg" "$rom"
