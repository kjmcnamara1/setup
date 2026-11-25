#!/usr/bin/env bash
# One-way mirror NAS -> bee for small systems' ROMs and all BIOS files, so those
# systems keep working when the NAS is down. The NAS is the master copy.
# Safety: never runs `--delete` against a source that is unmounted, missing, or empty.
set -euo pipefail

# System list: $BEE_LOCAL_SYSTEMS, else the file mise renders from
# [vars] bee_local_systems in conf.d/mise.bee.toml.
BEE_LOCAL_SYSTEMS_FILE="${BEE_LOCAL_SYSTEMS_FILE:-$HOME/.config/bee/local-systems}"
if [[ -z "${BEE_LOCAL_SYSTEMS:-}" ]]; then
  if [[ ! -r "$BEE_LOCAL_SYSTEMS_FILE" ]]; then
    printf 'bee-mirror-roms: %s missing (run mise bootstrap); skipping\n' "$BEE_LOCAL_SYSTEMS_FILE" >&2
    exit 0
  fi
  BEE_LOCAL_SYSTEMS="$(tr -s '[:space:]' ' ' <"$BEE_LOCAL_SYSTEMS_FILE")"
fi
BEE_NAS_MOUNT="${BEE_NAS_MOUNT:-/mnt/nasro}"
BEE_NAS_LIBRARY="${BEE_NAS_LIBRARY:-$BEE_NAS_MOUNT/media/library}"
BEE_LOCAL_GAMES="${BEE_LOCAL_GAMES:-$HOME/Games}"

log() { printf 'bee-mirror-roms: %s\n' "$*" >&2; }

if [[ "${BEE_SKIP_MOUNT_CHECK:-0}" != 1 ]]; then
  timeout 20 ls "$BEE_NAS_MOUNT/" >/dev/null 2>&1 || true # trigger the automount
  if ! findmnt -n -t nfs,nfs4 --mountpoint "$BEE_NAS_MOUNT" >/dev/null 2>&1; then
    log "$BEE_NAS_MOUNT is not an NFS mount right now; skipping"
    exit 0
  fi
fi

non_empty_dir() { [[ -d "$1" ]] && [[ -n "$(find "$1" -mindepth 1 -print -quit 2>/dev/null)" ]]; }

# mirror_dir <src> <dst>: rsync with --delete, but only from a non-empty source.
# rsync skips deletions by itself if it hits I/O errors (no --ignore-errors).
mirror_dir() {
  local src="$1" dst="$2"
  if ! non_empty_dir "$src"; then
    log "source $src missing or empty; leaving $dst alone"
    return 0
  fi
  mkdir -p "$dst"
  rsync -a --delete "$src/" "$dst/" || log "rsync $src failed (rc=$?); will retry next run"
}

read -r -a systems <<<"$BEE_LOCAL_SYSTEMS"
for sys in "${systems[@]}"; do
  mirror_dir "$BEE_NAS_LIBRARY/roms/$sys" "$BEE_LOCAL_GAMES/roms/$sys"
done
mirror_dir "$BEE_NAS_LIBRARY/bios" "$BEE_LOCAL_GAMES/bios"
exit 0
