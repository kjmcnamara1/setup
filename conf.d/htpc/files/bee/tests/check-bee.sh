#!/usr/bin/env bash
# Acceptance checks, run on bee as media after `mise bootstrap`.
# Usage: check-bee.sh <packages|mounts|nextcloud|mirror|esde|cores|seed|emulators|backup|all>
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

SYNC="$HOME/Nextcloud/Games/bee"
GAMES="$HOME/Games"
NASRO="/mnt/nasro/media/library"
NAS="/mnt/NAS/media/library"

PACMAN_PKGS=(retroarch retroarch-assets-xmb libretro-core-info libretro-nestopia libretro-snes9x
  libretro-gambatte libretro-mgba libretro-genesis-plus-gx libretro-mupen64plus-next
  libretro-beetle-psx-hw libretro-melonds ppsspp dolphin-emu nextcloud-client rsync unzip
  mesa vulkan-intel intel-media-driver lib32-mesa lib32-vulkan-intel steam)
AUR_PKGS=(emulationstation-de pcsx2-latest-bin rpcs3-bin cemu-bin xemu-bin ryujinx-bin
  shadps4-bin xenia-canary-bin azahar)

check_packages() {
  assert_eq 1000 "$(id -u media)" "media uid is 1000"
  assert_cmd "media is in group nas" bash -c 'id -nG media | tr " " "\n" | grep -qx nas'
  assert_eq 3000 "$(getent group nas | cut -d: -f3)" "group nas has gid 3000"
  assert_cmd "multilib enabled" grep -q '^\[multilib\]' /etc/pacman.conf
  local p
  for p in "${PACMAN_PKGS[@]}" "${AUR_PKGS[@]}"; do assert_cmd "installed: $p" pacman -Q "$p"; done
}

check_mounts() {
  ls "$NASRO/roms" >/dev/null 2>&1   # trigger automount
  ls "$NAS/roms" >/dev/null 2>&1
  local ro rw
  ro="$(findmnt -n -o OPTIONS -t nfs,nfs4 /mnt/nasro || true)"
  rw="$(findmnt -n -o OPTIONS -t nfs,nfs4 /mnt/NAS || true)"
  assert_cmd "/mnt/nasro is ro" grep -qw ro <<<"${ro//,/ }"
  assert_cmd "/mnt/nasro is soft" grep -qw soft <<<"${ro//,/ }"
  assert_cmd "/mnt/NAS is hard" grep -qw hard <<<"${rw//,/ }"
  assert_eq 1 "$(grep -c ' /mnt/NAS ' /etc/fstab)" "exactly one /mnt/NAS line in fstab"
  assert_cmd "/mnt/NAS is automounted (mise env includes nas)" grep -q ' /mnt/NAS .*x-systemd.automount' /etc/fstab
  assert_cmd "/mnt/nasro is not writable" bash -c "! touch '$NASRO/.bee-write-test' 2>/dev/null"
}

check_nextcloud() {
  assert_eq 600 "$(stat -c %a "$HOME/.netrc" 2>/dev/null)" "~/.netrc mode 600"
  assert_cmd "sync timer active" systemctl --user is-active dev.mise.bee-nextcloud-sync-timer.timer
  assert_cmd "sync service runs" systemctl --user start --wait dev.mise.bee-nextcloud-sync.service
  assert_file "$SYNC/.bee-synced-once" "a sync has succeeded"
  assert_cmd "NES saves present in synced folder" bash -c "compgen -G '$SYNC/saves/nes/*.srm'"
  assert_file "$SYNC/configs/es-de/settings"
}

check_mirror() {
  local sys n_src n_dst
  assert_cmd "mirror service runs" systemctl --user start --wait dev.mise.bee-mirror-roms.service
  for sys in nes snes gba psx; do
    n_src="$(find "$NASRO/roms/$sys" -type f 2>/dev/null | wc -l)"
    n_dst="$(find "$GAMES/roms/$sys" -type f 2>/dev/null | wc -l)"
    assert_eq "$n_src" "$n_dst" "mirror file count for $sys"
  done
  assert_file "$GAMES/bios/psx/scph1001.bin"
  assert_no_file "$GAMES/roms/ps2" "big systems are not mirrored"
  assert_cmd "mirror timer active" systemctl --user is-active dev.mise.bee-mirror-roms-timer.timer
}

check_esde() {
  assert_symlink_into "$HOME/ES-DE/settings" "$SYNC/configs/es-de"
  assert_symlink_into "$HOME/ES-DE/gamelists" "$SYNC/configs/es-de"
  assert_symlink_into "$HOME/ES-DE/collections" "$SYNC/configs/es-de"
  assert_file "$HOME/ES-DE/settings/es_settings.xml"
  assert_cmd "es_systems.xml is valid XML" xmllint --noout "$HOME/ES-DE/custom_systems/es_systems.xml"
  assert_eq 20 "$(grep -c '<system>' "$HOME/ES-DE/custom_systems/es_systems.xml")" "20 systems (no lutris)"
  assert_cmd "nes path is local" grep -q "<path>$GAMES/roms/nes</path>" "$HOME/ES-DE/custom_systems/es_systems.xml"
  assert_cmd "ps2 path is NAS ro" grep -q "<path>$NASRO/roms/ps2</path>" "$HOME/ES-DE/custom_systems/es_systems.xml"
}

check_cores() {
  local c
  for c in fceumm swanstation; do
    if [[ -e "$HOME/.config/retroarch/cores/${c}_libretro.so" ]]; then _pass "optional core present: $c"
    else printf 'INFO  optional core missing: %s (packaged fallback will be used; Batocera save states for it will not load)\n' "$c"; fi
  done
}

check_seed() {
  assert_file "$SYNC/configs/ryujinx/Config.json"
  assert_file "$SYNC/configs/ryujinx/bis"
  assert_file "$SYNC/saves/ps3/home"
  assert_file "$SYNC/configs/rpcs3/config.yml"
  assert_file "$HOME/.local/share/xemu/xbox_hdd.qcow2"
  assert_file "$HOME/.local/share/Cemu/keys.txt"
}

check_emulators() {
  assert_symlink_into "$HOME/.config/retroarch" "$SYNC/configs/retroarch"
  # mid-weight
  assert_symlink_into "$HOME/.config/ppsspp/PSP/SAVEDATA" "$SYNC/saves/psp"
  assert_symlink_into "$HOME/.config/ppsspp/PSP/PPSSPP_STATE" "$SYNC/saves/psp"
  assert_symlink_into "$HOME/.config/ppsspp/PSP/SYSTEM" "$SYNC/configs/ppsspp"
  assert_symlink_into "$HOME/.config/PCSX2/inis" "$SYNC/configs/pcsx2"
  assert_contains "$HOME/.config/PCSX2/inis/PCSX2.ini" "$GAMES/bios/ps2"
  assert_symlink_into "$HOME/.config/dolphin-emu" "$SYNC/configs/dolphin-emu"
  local d
  for d in GC Wii StateSaves; do assert_symlink_into "$HOME/.local/share/dolphin-emu/$d" "$SYNC/saves/dolphin-emu"; done
  # heavy (whole config dirs linked; see conf.d/htpc/mise.emu.toml)
  assert_symlink_into "$HOME/.config/Cemu" "$SYNC/configs/cemu"
  assert_symlink_into "$HOME/.local/share/Cemu/mlc01" "$SYNC/saves/wiiu"
  assert_symlink_into "$HOME/.config/rpcs3" "$SYNC/configs/rpcs3"
  assert_contains "$HOME/.config/rpcs3/config/vfs.yml" "/dev_hdd0/: $HOME/.local/share/rpcs3/dev_hdd0/"
  assert_symlink_into "$HOME/.local/share/rpcs3/dev_hdd0/home" "$SYNC/saves/ps3"
  assert_symlink_into "$HOME/.local/share/rpcs3/dev_hdd0/game" "$NAS/emulators/configs/rpcs3/dev_hdd0/game"
  assert_symlink_into "$HOME/.config/Ryujinx" "$SYNC/configs/ryujinx"
  assert_file "$HOME/.config/Ryujinx/bis" "Switch saves present"
  assert_eq "$NASRO/roms/switch" "$(jq -r '.game_dirs[0]' "$HOME/.config/Ryujinx/Config.json" 2>/dev/null)" "Ryujinx game_dirs"
  assert_symlink_into "$HOME/.config/azahar-emu" "$SYNC/configs/azahar"
  assert_symlink_into "$HOME/.local/share/azahar-emu/sdmc" "$SYNC/saves/3ds"
  assert_symlink_into "$HOME/.local/share/azahar-emu/nand" "$SYNC/saves/3ds"
  assert_symlink_into "$HOME/.local/share/xemu/xemu" "$SYNC/configs/xemu"
  assert_contains "$HOME/.local/share/xemu/xemu/xemu.toml" "$HOME/.local/share/xemu/xbox_hdd.qcow2"
  assert_symlink_into "$HOME/.local/share/shadPS4/user/savedata" "$SYNC/saves/ps4"
  assert_symlink_into "$HOME/.local/share/Xenia/content" "$SYNC/saves/xbox360"
  # nothing hot or huge in the synced folder
  assert_eq "" "$(find "$SYNC/saves" \( -iname cache -o -iname shadercache -o -name '*.log' -o -name '*.qcow2' \) -print -quit 2>/dev/null)" "no caches/logs/qcow2 in synced saves"
}

check_backup() {
  assert_cmd "backup timer active" systemctl --user is-active dev.mise.bee-nas-backup-timer.timer
  assert_cmd "backup service runs" systemctl --user start --wait dev.mise.bee-nas-backup.service
  assert_file "$NAS/backups/bee/latest"
}

section="${1:-all}"
case "$section" in
  all) for s in packages mounts nextcloud mirror esde cores seed emulators backup; do echo "== $s"; "check_$s"; done ;;
  packages|mounts|nextcloud|mirror|esde|cores|seed|emulators|backup) "check_$section" ;;
  *) echo "unknown section: $section" >&2; exit 2 ;;
esac
echo "---- $BEE_FAILS failed"
[[ $BEE_FAILS -eq 0 ]]
