#!/usr/bin/env bash
# Install Batocera's default NES/PSX cores (fceumm, swanstation) from the libretro
# buildbot into ~/.config/retroarch/cores, so Batocera save states still load.
# Optional: any failure is logged and bee-ra.sh falls back to the packaged cores.
set -euo pipefail

BEE_CORE_DIR="${BEE_CORE_DIR:-$HOME/.config/retroarch/cores}"
BEE_BUILDBOT="${BEE_BUILDBOT:-https://buildbot.libretro.com/nightly/linux/x86_64/latest}"
CORES=(fceumm swanstation)

log() { printf 'bee-fetch-cores: %s\n' "$*" >&2; }

mkdir -p "$BEE_CORE_DIR"
for core in "${CORES[@]}"; do
  so="${core}_libretro.so"
  [[ -f "$BEE_CORE_DIR/$so" ]] && continue
  work="$(mktemp -d)"
  if curl -fsSL -m 120 -o "$work/$so.zip" "$BEE_BUILDBOT/$so.zip" \
    && unzip -q -o "$work/$so.zip" "$so" -d "$work/out" \
    && [[ -s "$work/out/$so" ]]; then
    install -m 0644 "$work/out/$so" "$BEE_CORE_DIR/$so"
    log "installed $so"
  else
    log "could not fetch $so; the packaged fallback core will be used"
  fi
  rm -rf "$work"
done
exit 0
