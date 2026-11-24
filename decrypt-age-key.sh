#!/usr/bin/env bash
# Decrypt the age key that unlocks mise's encrypted dotfiles. Bootstrap pre-packages hook.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # the mise config dir
key="$dir/age.txt"
[[ -s "$key" ]] && exit 0

if ! { : > /dev/tty; } 2> /dev/null; then
  echo "age: no terminal to ask for the password; run 'mise bootstrap' interactively" >&2
  exit 1
fi

tmp="$(mktemp "$key.XXXXXX")" # mode 600
trap 'rm -f "$tmp"' EXIT
echo "Enter the password for your age key" > /dev/tty
mise x age@latest -- age -d "$dir/age.txt.age" > "$tmp" # age reads the password from /dev/tty
mv "$tmp" "$key"
trap - EXIT
