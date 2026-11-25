#!/usr/bin/env bash
# First-run seeds from the NAS (Batocera-era emulator configs, keys, xemu disk).
# Each item is copied only when its destination is missing or an empty directory,
# so anything already synced from Nextcloud or changed on bee always wins.
# Only runs after at least one successful Nextcloud sync (marker written by
# bee-nextcloud-sync.sh), so a down server can't cause stale-vs-real conflicts.
# Runs in the pre-dotfiles hook, after the Nextcloud pull and before [dotfiles]
# links/merges (merges would otherwise create partial config files first).
set -euo pipefail

BEE_NAS_MOUNT="${BEE_NAS_MOUNT:-/mnt/NAS}"
BEE_NAS_LIBRARY="${BEE_NAS_LIBRARY:-$BEE_NAS_MOUNT/media/library}"
BEE_SYNC_ROOT="${BEE_SYNC_ROOT:-$HOME/Nextcloud/Games/bee}"
BEE_HOME="${BEE_HOME:-$HOME}"

log() { printf 'bee-seed: %s\n' "$*" >&2; }

if [[ "${BEE_SKIP_MOUNT_CHECK:-0}" != 1 ]]; then
  timeout 20 ls "$BEE_NAS_MOUNT/" >/dev/null 2>&1 || true # trigger the automount
  if ! findmnt -n -t nfs,nfs4 --mountpoint "$BEE_NAS_MOUNT" >/dev/null 2>&1; then
    log "$BEE_NAS_MOUNT is not mounted; skipping seeds"
    exit 0
  fi
fi

# Fail closed on a dead NAS: a mounted `hard` NFS share whose server is gone still
# shows in findmnt, and any later find/cp/rsync would block forever.
if ! timeout -k 2 10 stat -t "$BEE_NAS_LIBRARY" >/dev/null 2>&1; then
  log "$BEE_NAS_LIBRARY is not responding; skipping"
  exit 0
fi

if [[ ! -e "$BEE_SYNC_ROOT/.bee-synced-once" ]]; then
  log "no successful Nextcloud sync yet; not seeding (would conflict with synced data)"
  exit 0
fi

is_empty_dir() { [[ -d "$1" ]] && [[ -z "$(find "$1" -mindepth 1 -print -quit)" ]]; }

# seed <src> <dst>: copy file or directory src to dst if dst is missing/empty.
seed() {
  local src="$1" dst="$2"
  if [[ ! -e "$src" ]]; then return 0; fi
  if [[ -e "$dst" ]] && ! is_empty_dir "$dst"; then return 0; fi
  mkdir -p "$(dirname "$dst")"
  if [[ -d "$src" ]]; then
    mkdir -p "$dst"
    cp -a "$src/." "$dst/"
  else
    cp -a "$src" "$dst"
  fi
  log "seeded $dst"
}

C="$BEE_NAS_LIBRARY/emulators/configs"
S="$BEE_SYNC_ROOT"

# ~/.config/Ryujinx is linked whole to configs/ryujinx, so Switch saves (bis/) live there.
for f in Config.json profiles system sdcard bis; do seed "$C/Ryujinx/$f" "$S/configs/ryujinx/$f"; done

for f in settings.xml controllerProfiles; do seed "$C/Cemu/$f" "$S/configs/cemu/$f"; done
seed "$BEE_NAS_LIBRARY/bios/cemu/keys.txt" "$BEE_HOME/.local/share/Cemu/keys.txt"

# games.yml is not seeded: it holds stale /home/kjm paths and RPCS3 rebuilds it.
for f in config.yml custom_configs input_configs GuiConfigs patches; do
  seed "$C/rpcs3/$f" "$S/configs/rpcs3/$f"
done
seed "$C/rpcs3/dev_hdd0/home" "$S/saves/ps3/home"

for f in xbox_hdd.qcow2 xemu_eeprom.bin; do
  seed "$BEE_NAS_LIBRARY/backups/bee/xbox/$f" "$BEE_HOME/.local/share/xemu/$f"
done
exit 0
