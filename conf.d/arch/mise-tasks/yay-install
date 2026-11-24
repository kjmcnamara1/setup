#!/usr/bin/env bash
# Install yay (AUR helper) if missing. Runs as the bootstrap pre-packages hook.
set -euo pipefail

if ! command -v pacman > /dev/null; then
  exit 0
fi
if ! command -v yay > /dev/null; then
  sudo pacman -S --needed --noconfirm git base-devel
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
fi
