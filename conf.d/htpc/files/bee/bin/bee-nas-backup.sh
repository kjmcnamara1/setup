#!/usr/bin/env bash
# Daily plain-file snapshot of bee's game setup to the NAS, browsable without Nextcloud:
#   <root>/snapshots/YYYY-MM-DD/games/  <- ~/Nextcloud/Games/bee (same excludes as the sync)
#   <root>/snapshots/YYYY-MM-DD/xemu/   <- xemu HDD image + EEPROM (local-only files)
#   <root>/latest -> snapshots/<newest>
# Unchanged files are hard links to the previous snapshot. Keeps the newest $BEE_KEEP.
set -euo pipefail

BEE_NAS_MOUNT="${BEE_NAS_MOUNT:-/mnt/NAS}"
BEE_NAS_LIBRARY="${BEE_NAS_LIBRARY:-$BEE_NAS_MOUNT/media/library}"
BEE_BACKUP_ROOT="${BEE_BACKUP_ROOT:-$BEE_NAS_LIBRARY/backups/bee}"
BEE_SYNC_ROOT="${BEE_SYNC_ROOT:-$HOME/Nextcloud/Games/bee}"
BEE_HOME="${BEE_HOME:-$HOME}"
BEE_KEEP="${BEE_KEEP:-30}"
BEE_DATE="${BEE_DATE:-$(date +%F)}"
EXCLUDE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../nextcloud" && pwd)/sync-exclude.lst"

log() { printf 'bee-nas-backup: %s\n' "$*" >&2; }

if [[ "${BEE_SKIP_MOUNT_CHECK:-0}" != 1 ]]; then
  timeout 20 ls "$BEE_NAS_MOUNT/" >/dev/null 2>&1 || true # trigger the automount
  if ! findmnt -n -t nfs,nfs4 --mountpoint "$BEE_NAS_MOUNT" >/dev/null 2>&1; then
    log "$BEE_NAS_MOUNT is not mounted; skipping"
    exit 0
  fi
fi

# Fail closed on a dead NAS: a mounted `hard` NFS share whose server is gone still
# shows in findmnt, and any later find/cp/rsync would block forever.
if ! timeout -k 2 10 stat -t "$BEE_NAS_LIBRARY" >/dev/null 2>&1; then
  log "$BEE_NAS_LIBRARY is not responding; skipping"
  exit 0
fi

snap="$BEE_BACKUP_ROOT/snapshots/$BEE_DATE"
mkdir -p "$snap/games" "$snap/xemu"
prev=() prevx=()
if [[ -d "$BEE_BACKUP_ROOT/latest/" ]] && [[ "$(readlink -f "$BEE_BACKUP_ROOT/latest")" != "$(readlink -f "$snap")" ]]; then
  prev_dir="$(readlink -f "$BEE_BACKUP_ROOT/latest")"
  prev=(--link-dest="$prev_dir/games")
  prevx=(--link-dest="$prev_dir/xemu")
fi

if [[ -d "$BEE_SYNC_ROOT" ]]; then
  rsync -a --delete --exclude-from="$EXCLUDE" "${prev[@]}" "$BEE_SYNC_ROOT/" "$snap/games/"
fi
xemu_files=()
for f in xbox_hdd.qcow2 xemu_eeprom.bin; do
  [[ -f "$BEE_HOME/.local/share/xemu/$f" ]] && xemu_files+=("$BEE_HOME/.local/share/xemu/$f")
done
if [[ ${#xemu_files[@]} -gt 0 ]]; then
  rsync -a "${prevx[@]}" "${xemu_files[@]}" "$snap/xemu/"
fi

ln -sfn "snapshots/$BEE_DATE" "$BEE_BACKUP_ROOT/latest"

mapfile -t snaps < <(find "$BEE_BACKUP_ROOT/snapshots" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
excess=$(( ${#snaps[@]} - BEE_KEEP ))
for (( i = 0; i < excess; i++ )); do
  rm -rf "${BEE_BACKUP_ROOT:?}/snapshots/${snaps[$i]}"
done
log "snapshot $snap done (${#snaps[@]} total before pruning, keep $BEE_KEEP)"
exit 0
