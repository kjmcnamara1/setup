# Mise Setup

## Arch Linux

### Installation

`archinstall`

OR

```sh
# Increase size of archiso CopyOnWrite filesystem
mount -o remount,size=2G /run/archiso/cowspace

pacman -Syu --noconfirm --ignore linux git mise && pacman -Scc
mise bootstrap --adopt kjmcnamara1/setup --only dotfiles

mise -E arch run arch-install
```

### Bootstrap

```sh
# Global config
mise bootstrap --adopt kjmcnamara1/setup -E <hostname> --save-env
# Tracked files history
mise bootstrap --adopt 'kjmcnamara1/setup?ref=history' --replace-history --yes
```
