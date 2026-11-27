#!/usr/bin/env bash
# Sync ~/Nextcloud/Games/bee <-> Nextcloud /Games/bee with nextcloudcmd (netrc login).
#   --init  also create the local folder skeleton first (symlink targets for [dotfiles]).
# Never fails bootstrap: an unreachable server is logged and skipped.
set -euo pipefail

BEE_SYNC_ROOT="${BEE_SYNC_ROOT:-$HOME/Nextcloud/Games/bee}"
BEE_NC_URL="${BEE_NC_URL:-http://192.168.0.10:8096}"
BEE_NC_BIN="${BEE_NC_BIN:-nextcloudcmd}"
EXCLUDE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../nextcloud" && pwd)/sync-exclude.lst"

SAVES=(nes snes gbc gba megadrive n64 nds psx psp ps2 ps3 ps4 gamecube wii wiiu switch 3ds
  xbox xbox360 dolphin-emu)
CONFIGS=(es-de/gamelists es-de/collections es-de/settings retroarch ppsspp pcsx2 dolphin-emu
  cemu rpcs3 ryujinx azahar xemu shadps4 xenia)
# Every symlink target used by [dotfiles] in conf.d/htpc/mise.emu.toml must be listed
# here (tests/test-scripts.sh: test_sync_init_covers_every_link_target).
LINK_TARGETS=(
  saves/psp/PSP/SAVEDATA saves/psp/PSP/PPSSPP_STATE configs/ppsspp/SYSTEM
  configs/pcsx2/inis
  saves/dolphin-emu/GC saves/dolphin-emu/Wii saves/dolphin-emu/StateSaves
  saves/ps3/home configs/rpcs3/config
  saves/3ds/citra-emu/sdmc saves/3ds/citra-emu/nand
)

log() { printf 'bee-nextcloud-sync: %s\n' "$*" >&2; }

if [[ "${1:-}" == "--init" ]]; then
  for d in "${SAVES[@]}"; do mkdir -p "$BEE_SYNC_ROOT/saves/$d"; done
  for d in "${CONFIGS[@]}"; do mkdir -p "$BEE_SYNC_ROOT/configs/$d"; done
  for d in "${LINK_TARGETS[@]}"; do mkdir -p "$BEE_SYNC_ROOT/$d"; done
fi
mkdir -p "$BEE_SYNC_ROOT"

if ! curl -fsm5 "$BEE_NC_URL/status.php" >/dev/null 2>&1; then
  log "server $BEE_NC_URL unreachable; skipping sync"
  exit 0
fi

lock="${XDG_RUNTIME_DIR:-/tmp}/bee-nextcloud-sync.lock"
exec 9>"$lock"
if ! flock -n 9; then
  log "another sync is running; skipping"
  exit 0
fi

# nextcloudcmd fails (exit 1, no message) if the remote --path folder is missing,
# so create each segment first. MKCOL: 201 = created, 405 = already exists.
remote=""
for seg in Games bee; do
  remote+="/$seg"
  code="$(curl -s -m10 -o /dev/null -w '%{http_code}' --netrc-optional -X MKCOL \
    "$BEE_NC_URL/remote.php/webdav$remote" || true)"
  case "$code" in
    201) log "created remote folder $remote" ;;
    405) ;;
    *) log "could not create remote folder $remote (HTTP $code); check ~/.netrc" ;;
  esac
done

if "$BEE_NC_BIN" -n --non-interactive -s --path /Games/bee \
  --exclude-anchored "$EXCLUDE" "$BEE_SYNC_ROOT" "$BEE_NC_URL"; then
  # bee-seed.sh only seeds after a first successful sync (hidden files are not
  # uploaded by nextcloudcmd without -h, so this marker stays local).
  touch "$BEE_SYNC_ROOT/.bee-synced-once"
else
  log "nextcloudcmd failed (will retry on next timer run)"
fi
exit 0
