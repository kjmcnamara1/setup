#!/usr/bin/env bash
# Decrypt SSH private keys on first bootstrap. Runs as the ssh module's post-packages hook.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
identity="${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}/age.txt"
keys=(aur github)

missing=()
for k in "${keys[@]}"; do
  [[ -s "$HOME/.ssh/$k" ]] || missing+=("$k")
done
((${#missing[@]})) || exit 0 # everything's in place: rerun-safe no-op

if [[ ! -s "$identity" ]]; then
  if ! { : > /dev/tty; } 2> /dev/null; then
    echo "ssh: no terminal to ask for the age password; skipping ${missing[*]}. Rerun 'mise bootstrap' interactively." >&2
    exit 0
  fi
  echo "ssh: enter the password to unlock your age key" > /dev/tty
  tmp="$(mktemp "${identity}.XXXXXX")" # mode 600
  trap 'rm -f "$tmp"' EXIT
  age -d "$here/age.txt.age" > "$tmp" # age reads the password from /dev/tty
  mv "$tmp" "$identity"
  trap - EXIT
fi

install -d -m 700 "$HOME/.ssh"
for k in "${missing[@]}"; do
  tmp="$(mktemp "$HOME/.ssh/.$k.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  age -d -i "$identity" "$here/$k.age" > "$tmp"
  mv "$tmp" "$HOME/.ssh/$k"
  trap - EXIT
done
