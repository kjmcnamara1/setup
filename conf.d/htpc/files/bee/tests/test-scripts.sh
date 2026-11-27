#!/usr/bin/env bash
# Unit tests for files/bee/bin/*.sh. Runs anywhere (angel or bee); touches only temp dirs.
# Usage: test-scripts.sh [test_name ...]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$(cd "$HERE/../bin" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

# ---------------------------------------------------------------- helpers
# Serve a directory over HTTP on a free port; sets $srv_pid and $srv_url.
serve_dir() {
  local dir="$1" port
  port="$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')"
  python3 -I -m http.server "$port" --bind 127.0.0.1 --directory "$dir" >/dev/null 2>&1 &
  srv_pid=$!
  srv_url="http://127.0.0.1:$port"
  for _ in $(seq 50); do curl -fsm1 "$srv_url/" >/dev/null 2>&1 && return 0; sleep 0.1; done
  return 1
}

# Stub that records its argv one per line into $STUB_OUT.
make_stub() { # <path>
  cat >"$1" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_OUT"
EOF
  chmod +x "$1"
}

# ---------------------------------------------------------------- nextcloud sync
test_sync_init_offline_creates_skeleton() {
  BEE_SYNC_ROOT="$tmp/sync" BEE_NC_URL="http://127.0.0.1:9" BEE_NC_BIN=/bin/false \
    bash "$BIN/bee-nextcloud-sync.sh" --init
  assert_eq 0 $? "exit 0 when server unreachable"
  assert_file "$tmp/sync/saves/psx"
  assert_file "$tmp/sync/saves/dolphin-emu"
  assert_file "$tmp/sync/configs/es-de/settings"
  assert_file "$tmp/sync/configs/ryujinx"
}

# Every symlink source in conf.d/htpc/mise.emu.toml that points into the synced folder
# must be created by --init, or [dotfiles] fails on a fresh bee.
test_sync_init_covers_every_link_target() {
  BEE_SYNC_ROOT="$tmp/sync" BEE_NC_URL="http://127.0.0.1:9" bash "$BIN/bee-nextcloud-sync.sh" --init 2>/dev/null
  local src missing=0
  while IFS= read -r src; do
    if [[ ! -d "$tmp/sync/${src#\~/Nextcloud/Games/bee/}" ]]; then echo "FAIL  skeleton lacks $src"; missing=1; fi
  done < <(grep -oE 'source *= *"~/Nextcloud/Games/bee/[^"]+"' "$HERE/../../../mise.emu.toml" \
    | sed -E 's/.*"(~[^"]+)"/\1/' | grep -v '\.[a-z]*$')
  assert_eq 0 "$missing" "all link targets in skeleton"
}

test_sync_calls_client_with_path() {
  mkdir -p "$tmp/www" && echo '{"installed":true}' >"$tmp/www/status.php"
  serve_dir "$tmp/www"
  make_stub "$tmp/nc"
  STUB_OUT="$tmp/argv" BEE_SYNC_ROOT="$tmp/sync" BEE_NC_URL="$srv_url" BEE_NC_BIN="$tmp/nc" \
    bash "$BIN/bee-nextcloud-sync.sh"
  kill "$srv_pid"
  assert_contains "$tmp/argv" "-n"
  assert_eq "/Games/bee" "$(grep -A1 -x -- '--path' "$tmp/argv" | tail -1)" "--path /Games/bee"
  assert_eq "$srv_url" "$(tail -1 "$tmp/argv")" "server url is last arg"
  assert_eq "$tmp/sync" "$(tail -2 "$tmp/argv" | head -1)" "local dir is second to last"
}

# ---------------------------------------------------------------- ROM/BIOS mirror
mirror() { # runs the mirror against $tmp/nas -> $tmp/local
  BEE_NAS_LIBRARY="$tmp/nas" BEE_LOCAL_GAMES="$tmp/local" BEE_SKIP_MOUNT_CHECK=1 \
    bash "$BIN/bee-mirror-roms.sh"
}

test_mirror_copies_listed_systems_only() {
  mkdir -p "$tmp/nas/roms/nes" "$tmp/nas/roms/ps2"
  echo a >"$tmp/nas/roms/nes/a.nes"; echo b >"$tmp/nas/roms/ps2/b.iso"
  BEE_LOCAL_SYSTEMS="nes" mirror
  assert_file "$tmp/local/roms/nes/a.nes"
  assert_no_file "$tmp/local/roms/ps2"
}

test_mirror_handles_odd_filenames() {
  mkdir -p "$tmp/nas/roms/nes"
  echo z >"$tmp/nas/roms/nes/Legend of Zelda, The (U) (PRG1) [!] it's.nes"
  BEE_LOCAL_SYSTEMS="nes" mirror
  assert_file "$tmp/local/roms/nes/Legend of Zelda, The (U) (PRG1) [!] it's.nes"
}

test_mirror_deletes_removed_roms() {
  mkdir -p "$tmp/nas/roms/nes" "$tmp/local/roms/nes"
  echo a >"$tmp/nas/roms/nes/a.nes"; echo old >"$tmp/local/roms/nes/gone.nes"
  BEE_LOCAL_SYSTEMS="nes" mirror
  assert_no_file "$tmp/local/roms/nes/gone.nes" "rom removed on NAS is removed locally"
}

test_mirror_skips_empty_source() {
  mkdir -p "$tmp/nas/roms/nes" "$tmp/local/roms/nes"
  echo keep >"$tmp/local/roms/nes/keep.nes"
  BEE_LOCAL_SYSTEMS="nes" mirror
  assert_file "$tmp/local/roms/nes/keep.nes" "empty source never wipes local copy"
}

test_mirror_skips_missing_source() {
  mkdir -p "$tmp/nas/roms" "$tmp/local/roms/nes"
  echo keep >"$tmp/local/roms/nes/keep.nes"
  BEE_LOCAL_SYSTEMS="nes" mirror
  assert_file "$tmp/local/roms/nes/keep.nes" "missing source never wipes local copy"
}

test_mirror_skips_when_not_mounted() {
  mkdir -p "$tmp/mnt/media/library/roms/nes" "$tmp/local/roms/nes"
  echo a >"$tmp/mnt/media/library/roms/nes/a.nes"; echo keep >"$tmp/local/roms/nes/keep.nes"
  BEE_LOCAL_SYSTEMS="nes" BEE_NAS_MOUNT="$tmp/mnt" BEE_LOCAL_GAMES="$tmp/local" \
    bash "$BIN/bee-mirror-roms.sh"
  assert_eq 0 $? "exit 0"
  assert_file "$tmp/local/roms/nes/keep.nes" "local untouched"
  assert_no_file "$tmp/local/roms/nes/a.nes" "nothing copied from a non-NFS path"
}

test_mirror_reads_systems_file() {
  mkdir -p "$tmp/nas/roms/snes" "$tmp/nas/roms/nes"
  echo s >"$tmp/nas/roms/snes/s.sfc"; echo n >"$tmp/nas/roms/nes/n.nes"
  echo "snes" >"$tmp/systems"
  BEE_LOCAL_SYSTEMS_FILE="$tmp/systems" mirror
  assert_file "$tmp/local/roms/snes/s.sfc"
  assert_no_file "$tmp/local/roms/nes" "only systems listed in the file"
}

test_mirror_bios() {
  mkdir -p "$tmp/nas/bios/psx" "$tmp/nas/roms"
  echo b >"$tmp/nas/bios/psx/scph1001.bin"; echo c >"$tmp/nas/bios/Complex_4627.bin"
  BEE_LOCAL_SYSTEMS="nes" mirror
  assert_file "$tmp/local/bios/psx/scph1001.bin"
  assert_file "$tmp/local/bios/Complex_4627.bin"
}

# ---------------------------------------------------------------- RetroArch launcher
ra_setup() { # creates two core dirs and a stub retroarch
  mkdir -p "$tmp/user-cores" "$tmp/sys-cores" "$tmp/run" "$tmp/home"
  make_stub "$tmp/retroarch"
}
ra() { # <system> <cores> <rom>
  STUB_OUT="$tmp/argv" HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/run" BEE_RA_BIN="$tmp/retroarch" \
    BEE_RA_CORE_DIRS="$tmp/user-cores:$tmp/sys-cores" bash "$BIN/bee-ra.sh" "$@"
}

test_ra_picks_first_core() {
  ra_setup
  touch "$tmp/user-cores/fceumm_libretro.so" "$tmp/sys-cores/nestopia_libretro.so"
  ra nes fceumm,nestopia "$tmp/a.nes"
  assert_eq "$tmp/user-cores/fceumm_libretro.so" "$(grep -A1 -x -- -L "$tmp/argv" | tail -1)" "uses preferred core"
}

test_ra_falls_back_to_second_core() {
  ra_setup
  touch "$tmp/sys-cores/nestopia_libretro.so"
  ra nes fceumm,nestopia "$tmp/a.nes"
  assert_eq "$tmp/sys-cores/nestopia_libretro.so" "$(grep -A1 -x -- -L "$tmp/argv" | tail -1)" "falls back to packaged core"
}

test_ra_quotes_rom_path() {
  ra_setup
  touch "$tmp/sys-cores/nestopia_libretro.so"
  local rom="$tmp/Legend of Zelda, The (U) (PRG1) [!] it's.nes"
  ra nes fceumm,nestopia "$rom"
  assert_eq "$rom" "$(tail -1 "$tmp/argv")" "rom path passed as one argument"
}

test_ra_writes_system_dirs() {
  ra_setup
  touch "$tmp/sys-cores/nestopia_libretro.so"
  ra nes nestopia "$tmp/a.nes"
  local cfg; cfg="$(grep -A1 -x -- --appendconfig "$tmp/argv" | tail -1)"
  assert_contains "$cfg" "savefile_directory = \"$tmp/home/Nextcloud/Games/bee/saves/nes\""
  assert_contains "$cfg" "savestate_directory = \"$tmp/home/Nextcloud/Games/bee/saves/nes\""
  assert_contains "$cfg" "system_directory = \"$tmp/home/Games/bios/nes\""
}

test_ra_no_core_exits_2() {
  ra_setup
  set +e; ra nes fceumm,nestopia "$tmp/a.nes"; local rc=$?; set -e
  assert_eq 2 "$rc" "exit 2 when no core found"
}

# ---------------------------------------------------------------- ES-DE template
# Renders a template with mise in an isolated HOME, with the given local-systems var.
render_tpl() { # <template> <local systems> <out>
  local h="$tmp/h"
  mkdir -p "$h/.config/mise/conf.d"
  printf '[settings.history]\nenabled = false\n' >"$h/.config/mise/config.toml"
  cat >"$h/.config/mise/conf.d/mise.t.toml" <<EOF
[vars]
  bee_local_systems = "$2"
[dotfiles]
  "~/out" = { source = "$1", mode = "template" }
EOF
  (cd "$h" && HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_STATE_HOME="$h/state" XDG_DATA_HOME="$h/data" \
    XDG_CACHE_HOME="$h/cache" MISE_ENV=t mise dot apply --yes >/dev/null 2>&1)
  cp "$h/out" "$3"
  sed -i "s#$h#/home/media#g" "$3"
}

test_es_systems_renders() {
  render_tpl "$HERE/../es-de/es_systems.xml.tera" "nes snes steam" "$tmp/es_systems.xml"
  assert_cmd "valid XML" python3 -I -c 'import sys,xml.etree.ElementTree as E;E.parse(sys.argv[1])' "$tmp/es_systems.xml"
  assert_eq 20 "$(grep -c '<system>' "$tmp/es_systems.xml")" "20 systems"
  assert_contains "$tmp/es_systems.xml" "<path>/home/media/Games/roms/nes</path>"
  assert_contains "$tmp/es_systems.xml" "<path>/home/media/Games/roms/steam</path>"
  assert_contains "$tmp/es_systems.xml" "<path>/mnt/nasro/media/library/roms/ps2</path>"
  assert_contains "$tmp/es_systems.xml" "<path>/mnt/nasro/media/library/roms/gba</path>"
  assert_contains "$tmp/es_systems.xml" "/home/media/.config/mise/files/bee/bin/bee-ra.sh nes fceumm,nestopia %ROM%"
  assert_cmd "no lutris system" bash -c "! grep -q '<name>lutris</name>' '$tmp/es_systems.xml'"
  assert_cmd "psx does not list .bin" bash -c "! python3 -I -c 'import sys,xml.etree.ElementTree as E;[print(s.findtext(\"extension\")) for s in E.parse(sys.argv[1]).getroot() if s.findtext(\"name\")==\"psx\"]' '$tmp/es_systems.xml' | grep -qi '\.bin'"
}

# ---------------------------------------------------------------- optional cores
test_fetch_skips_existing() {
  mkdir -p "$tmp/cores"; echo mine >"$tmp/cores/fceumm_libretro.so"; echo mine >"$tmp/cores/swanstation_libretro.so"
  BEE_CORE_DIR="$tmp/cores" BEE_BUILDBOT="http://127.0.0.1:9" bash "$BIN/bee-fetch-cores.sh"
  assert_eq mine "$(cat "$tmp/cores/fceumm_libretro.so")" "existing core untouched"
}

test_fetch_failure_is_nonfatal() {
  BEE_CORE_DIR="$tmp/cores" BEE_BUILDBOT="http://127.0.0.1:9" bash "$BIN/bee-fetch-cores.sh"
  assert_eq 0 $? "exit 0"
  assert_no_file "$tmp/cores/fceumm_libretro.so"
}

test_fetch_downloads_and_unzips() {
  mkdir -p "$tmp/www" "$tmp/z"
  for c in fceumm swanstation; do
    echo "$c-bin" >"$tmp/z/${c}_libretro.so"
    (cd "$tmp/z" && python3 -I -m zipfile -c "$tmp/www/${c}_libretro.so.zip" "${c}_libretro.so")
  done
  serve_dir "$tmp/www"
  BEE_CORE_DIR="$tmp/cores" BEE_BUILDBOT="$srv_url" bash "$BIN/bee-fetch-cores.sh"
  kill "$srv_pid"
  assert_eq fceumm-bin "$(cat "$tmp/cores/fceumm_libretro.so")" "fceumm installed"
  assert_eq swanstation-bin "$(cat "$tmp/cores/swanstation_libretro.so")" "swanstation installed"
}

# ---------------------------------------------------------------- seed
fake_nas() {
  local n="$tmp/nas"
  mkdir -p "$n/emulators/configs/Ryujinx/"{profiles,system,sdcard,bis/user/save} \
    "$n/emulators/configs/Cemu/controllerProfiles" \
    "$n/emulators/configs/rpcs3/"{custom_configs,input_configs,GuiConfigs,patches,dev_hdd0/home/00000001} \
    "$n/bios/cemu" "$n/backups/bee/xbox"
  echo '{"nas":1}' >"$n/emulators/configs/Ryujinx/Config.json"
  echo key >"$n/emulators/configs/Ryujinx/system/prod.keys"
  echo save >"$n/emulators/configs/Ryujinx/bis/user/save/0001"
  echo '<cemu/>' >"$n/emulators/configs/Cemu/settings.xml"
  echo pad >"$n/emulators/configs/Cemu/controllerProfiles/p.xml"
  echo cfg >"$n/emulators/configs/rpcs3/config.yml"
  echo g >"$n/emulators/configs/rpcs3/games.yml"
  echo s >"$n/emulators/configs/rpcs3/dev_hdd0/home/00000001/localusername"
  echo k >"$n/bios/cemu/keys.txt"
  echo hdd >"$n/backups/bee/xbox/xbox_hdd.qcow2"; echo ee >"$n/backups/bee/xbox/xemu_eeprom.bin"
  mkdir -p "$tmp/sync"; touch "$tmp/sync/.bee-synced-once"   # a first sync has happened
}
seed() {
  BEE_NAS_LIBRARY="$tmp/nas" BEE_SYNC_ROOT="$tmp/sync" BEE_HOME="$tmp/home" BEE_SKIP_MOUNT_CHECK=1 \
    bash "$BIN/bee-seed.sh"
}

test_seed_copies_when_missing() {
  fake_nas; mkdir -p "$tmp/sync/configs/ryujinx"   # skeleton dir exists but empty
  seed
  assert_eq '{"nas":1}' "$(cat "$tmp/sync/configs/ryujinx/Config.json")" "Ryujinx Config.json"
  assert_file "$tmp/sync/configs/ryujinx/system/prod.keys"
  assert_file "$tmp/sync/configs/ryujinx/bis/user/save/0001" "Switch saves live in the linked Ryujinx dir"
  assert_file "$tmp/sync/configs/cemu/settings.xml"
  assert_file "$tmp/sync/configs/cemu/controllerProfiles/p.xml"
  assert_file "$tmp/sync/configs/rpcs3/config.yml"
  assert_file "$tmp/sync/configs/rpcs3/custom_configs"
  assert_no_file "$tmp/sync/configs/rpcs3/games.yml" "stale games.yml not seeded"
  assert_file "$tmp/sync/saves/ps3/home/00000001/localusername"
  assert_file "$tmp/home/.local/share/Cemu/keys.txt"
  assert_file "$tmp/home/.local/share/xemu/xbox_hdd.qcow2"
  assert_file "$tmp/home/.local/share/xemu/xemu_eeprom.bin"
}

test_seed_never_overwrites() {
  fake_nas
  mkdir -p "$tmp/sync/configs/ryujinx" "$tmp/sync/saves/ps3/home" "$tmp/home/.local/share/xemu"
  echo mine >"$tmp/sync/configs/ryujinx/Config.json"
  echo mine >"$tmp/sync/saves/ps3/home/mine"
  echo mine >"$tmp/home/.local/share/xemu/xbox_hdd.qcow2"
  seed
  assert_eq mine "$(cat "$tmp/sync/configs/ryujinx/Config.json")" "Config.json kept"
  assert_no_file "$tmp/sync/saves/ps3/home/00000001" "non-empty save dir not merged into"
  assert_eq mine "$(cat "$tmp/home/.local/share/xemu/xbox_hdd.qcow2")" "qcow2 kept"
}

test_seed_nas_absent_exit0() {
  mkdir -p "$tmp/mnt"
  BEE_NAS_MOUNT="$tmp/mnt" BEE_SYNC_ROOT="$tmp/sync" BEE_HOME="$tmp/home" bash "$BIN/bee-seed.sh"
  assert_eq 0 $? "exit 0"
  assert_no_file "$tmp/sync/configs/ryujinx/Config.json"
}

# ---------------------------------------------------------------- merges keep user settings
# Applies one merge source onto a target with mise in an isolated HOME.
apply_merge() { # <merge source> <target file (created/edited)>
  local h="$tmp/h"
  mkdir -p "$h/.config/mise/conf.d"
  printf '[settings.history]\nenabled = false\n' >"$h/.config/mise/config.toml"
  printf '[dotfiles]\n  "%s/t" = { source = "%s", merge = true }\n' "$2" "$1" >"$h/.config/mise/conf.d/mise.t.toml"
  (cd "$h" && HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_STATE_HOME="$h/state" XDG_DATA_HOME="$h/data" \
    XDG_CACHE_HOME="$h/cache" MISE_ENV=t mise dot apply --yes >/dev/null 2>&1)
}

test_pcsx2_merge_keeps_user_settings() {
  cat >"$tmp/PCSX2.ini" <<'EOF'
[EmuCore/GS]
upscale_multiplier = 3

[Folders]
Bios = /somewhere/else
Cache = cache
EOF
  apply_merge "$HERE/../merge/pcsx2.ini" "$tmp/PCSX2.ini"
  assert_contains "$tmp/PCSX2.ini" "upscale_multiplier = 3" "user setting kept"
  assert_contains "$tmp/PCSX2.ini" "Cache = cache" "unlisted path key kept"
  assert_cmd "Bios forced to mirror" grep -Eq '^Bios ?= ?/home/media/Games/bios/ps2' "$tmp/PCSX2.ini"
  assert_cmd "MemoryCards set" grep -Eq '^MemoryCards ?= ?/home/media/Nextcloud/Games/bee/saves/ps2/pcsx2$' "$tmp/PCSX2.ini"
}

test_ryujinx_merge_sets_game_dirs() {
  printf '{"game_dirs":["/old"],"enable_vsync":false,"autoload_dirs":[]}' >"$tmp/Config.json"
  apply_merge "$HERE/../merge/ryujinx.json" "$tmp/Config.json"
  assert_eq '["/mnt/nasro/media/library/roms/switch"]' "$(jq -c .game_dirs "$tmp/Config.json")" "game_dirs"
  assert_eq '["/mnt/nasro/media/library/roms/switch/dlc-patch"]' "$(jq -c .autoload_dirs "$tmp/Config.json")" "autoload_dirs"
  assert_eq false "$(jq -c .enable_vsync "$tmp/Config.json")" "user setting kept"
}

test_xemu_merge_sets_files() {
  printf '[display.window]\nfullscreen_on_startup = true\n\n[sys.files]\nbootrom_path = "/x"\n' >"$tmp/xemu.toml"
  apply_merge "$HERE/../merge/xemu.toml" "$tmp/xemu.toml"
  assert_contains "$tmp/xemu.toml" "fullscreen_on_startup = true" "user setting kept"
  assert_contains "$tmp/xemu.toml" 'bootrom_path = "/home/media/Games/bios/xbox/mcpx_1.0.bin"'
  assert_contains "$tmp/xemu.toml" 'hdd_path = "/home/media/.local/share/xemu/xbox_hdd.qcow2"'
  assert_contains "$tmp/xemu.toml" 'flashrom_path = "/home/media/Games/bios/Complex_4627.bin"'
}

test_rpcs3_vfs_merge_sets_hdd0() {
  printf '$(EmulatorDir): ""\n/dev_hdd0/: $(EmulatorDir)dev_hdd0/\n/dev_flash/: $(EmulatorDir)dev_flash/\n' >"$tmp/vfs.yml"
  apply_merge "$HERE/../merge/rpcs3-vfs.yml" "$tmp/vfs.yml"
  assert_contains "$tmp/vfs.yml" "/dev_hdd0/: /home/media/.local/share/rpcs3/dev_hdd0/"
  assert_contains "$tmp/vfs.yml" '/dev_flash/: $(EmulatorDir)dev_flash/' "other mounts kept"
}

# ---------------------------------------------------------------- NAS backup
backup() { # [date]
  BEE_NAS_LIBRARY="$tmp" BEE_SYNC_ROOT="$tmp/sync" BEE_HOME="$tmp/home" BEE_BACKUP_ROOT="$tmp/bk" BEE_SKIP_MOUNT_CHECK=1 \
    BEE_DATE="${1:-2026-01-01}" BEE_KEEP="${KEEP:-30}" bash "$BIN/bee-nas-backup.sh"
}
backup_fixture() {
  mkdir -p "$tmp/sync/saves/nes" "$tmp/home/.local/share/xemu"
  echo s >"$tmp/sync/saves/nes/z.srm"
  echo h >"$tmp/home/.local/share/xemu/xbox_hdd.qcow2"; echo e >"$tmp/home/.local/share/xemu/xemu_eeprom.bin"
}

test_backup_creates_snapshot_and_latest() {
  backup_fixture; backup 2026-01-01
  assert_file "$tmp/bk/snapshots/2026-01-01/games/saves/nes/z.srm"
  assert_file "$tmp/bk/snapshots/2026-01-01/xemu/xbox_hdd.qcow2"
  assert_eq "snapshots/2026-01-01" "$(readlink "$tmp/bk/latest")" "latest points at snapshot"
}

test_backup_hardlinks_unchanged_files() {
  backup_fixture; backup 2026-01-01; backup 2026-01-02
  assert_eq "$(stat -c %i "$tmp/bk/snapshots/2026-01-01/games/saves/nes/z.srm")" \
    "$(stat -c %i "$tmp/bk/snapshots/2026-01-02/games/saves/nes/z.srm")" "unchanged file hard-linked"
}

test_backup_prunes_to_keep() {
  backup_fixture
  for d in 01 02 03 04; do KEEP=2 backup "2026-01-$d"; done
  assert_eq "2026-01-03 2026-01-04" "$(ls "$tmp/bk/snapshots" | tr '\n' ' ' | sed 's/ $//')" "kept newest 2"
}

test_backup_skips_when_not_mounted() {
  backup_fixture; mkdir -p "$tmp/mnt"
  BEE_NAS_MOUNT="$tmp/mnt" BEE_SYNC_ROOT="$tmp/sync" BEE_HOME="$tmp/home" BEE_BACKUP_ROOT="$tmp/bk" \
    bash "$BIN/bee-nas-backup.sh"
  assert_eq 0 $? "exit 0"
  assert_no_file "$tmp/bk"
}

# ---------------------------------------------------------------- config lint (review fixes)
BEE_TOML="$HERE/../../../mise.emu.toml"

# systemd never expands ~ and mise only expands a leading one: use %h.
test_exec_start_has_no_tilde() {
  assert_eq "" "$(grep -nE '^\s*exec_start\s*=\s*".*~' "$BEE_TOML")" "no ~ in exec_start (use %h)"
}

# A [dotfiles] source on the NAS makes the whole dotfiles step fail (or hang) when the NAS is down.
test_no_dotfile_source_on_nas() {
  assert_eq "" "$(grep -nE '^\s*source\s*=\s*"/mnt/' "$BEE_TOML")" "no dotfile source under /mnt"
}

test_retroarch_config_is_synced() {
  assert_cmd "~/.config/retroarch linked" grep -q '^\[dotfiles."~/.config/retroarch"\]' "$BEE_TOML"
  assert_cmd "cores excluded from sync" grep -qx 'configs/retroarch/cores' "$HERE/../nextcloud/sync-exclude.lst"
}

test_ra_sets_exit_hotkey() {
  ra_setup
  touch "$tmp/sys-cores/nestopia_libretro.so"
  ra nes nestopia "$tmp/a.nes"
  local cfg; cfg="$(grep -A1 -x -- --appendconfig "$tmp/argv" | tail -1)"
  assert_contains "$cfg" 'input_enable_hotkey_btn = "6"'
  assert_contains "$cfg" 'input_exit_emulator_btn = "7"'
}

# Seeding before Nextcloud has ever synced would create conflicts with the real data.
test_seed_waits_for_first_sync() {
  fake_nas; rm -f "$tmp/sync/.bee-synced-once"; mkdir -p "$tmp/sync"
  BEE_NAS_LIBRARY="$tmp/nas" BEE_SYNC_ROOT="$tmp/sync" BEE_HOME="$tmp/home" BEE_SKIP_MOUNT_CHECK=1 \
    bash "$BIN/bee-seed.sh"
  assert_no_file "$tmp/sync/configs/ryujinx/Config.json" "no seed before first successful sync"
}

test_sync_writes_marker_on_success() {
  mkdir -p "$tmp/www" && echo '{"installed":true}' >"$tmp/www/status.php"
  serve_dir "$tmp/www"; make_stub "$tmp/nc"
  STUB_OUT="$tmp/argv" BEE_SYNC_ROOT="$tmp/sync" BEE_NC_URL="$srv_url" BEE_NC_BIN="$tmp/nc" \
    bash "$BIN/bee-nextcloud-sync.sh"
  kill "$srv_pid"
  assert_file "$tmp/sync/.bee-synced-once"
}

test_sync_no_marker_when_client_fails() {
  mkdir -p "$tmp/www" && echo '{"installed":true}' >"$tmp/www/status.php"
  serve_dir "$tmp/www"
  BEE_SYNC_ROOT="$tmp/sync" BEE_NC_URL="$srv_url" BEE_NC_BIN=/bin/false bash "$BIN/bee-nextcloud-sync.sh"
  kill "$srv_pid"
  assert_no_file "$tmp/sync/.bee-synced-once"
}

# A dead NAS behind a mounted hard mount: the liveness probe must fail closed.
test_seed_skips_when_nas_unresponsive() {
  mkdir -p "$tmp/sync"; touch "$tmp/sync/.bee-synced-once"
  BEE_NAS_LIBRARY="$tmp/nonexistent" BEE_SYNC_ROOT="$tmp/sync" BEE_HOME="$tmp/home" BEE_SKIP_MOUNT_CHECK=1 \
    bash "$BIN/bee-seed.sh"
  assert_eq 0 $? "exit 0"
  assert_no_file "$tmp/home/.local/share" "nothing seeded"
}

test_backup_skips_when_nas_unresponsive() {
  backup_fixture
  BEE_NAS_LIBRARY="$tmp/nonexistent" BEE_SYNC_ROOT="$tmp/sync" BEE_HOME="$tmp/home" BEE_BACKUP_ROOT="$tmp/bk" \
    BEE_SKIP_MOUNT_CHECK=1 bash "$BIN/bee-nas-backup.sh"
  assert_eq 0 $? "exit 0"
  assert_no_file "$tmp/bk"
}

# nextcloudcmd exits 1 (silently) when its --path folder doesn't exist on the server,
# so the script must create /Games and /Games/bee over WebDAV before syncing.
test_sync_creates_remote_folder() {
  cat >"$tmp/dav.py" <<'EOF'
import http.server, sys
log = open(sys.argv[2], "a")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, body=b""):
        self.send_response(code); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        self.reply(200, b'{"installed":true}') if self.path == "/status.php" else self.reply(404)
    def do_MKCOL(self):
        log.write(self.path + "\n"); log.flush(); self.reply(201)
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
EOF
  local port
  port="$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')"
  python3 -I "$tmp/dav.py" "$port" "$tmp/mkcol" & srv_pid=$!
  srv_url="http://127.0.0.1:$port"
  for _ in $(seq 50); do curl -fsm1 "$srv_url/status.php" >/dev/null 2>&1 && break; sleep 0.1; done
  make_stub "$tmp/nc"
  STUB_OUT="$tmp/argv" HOME="$tmp/home" BEE_SYNC_ROOT="$tmp/sync" BEE_NC_URL="$srv_url" BEE_NC_BIN="$tmp/nc" \
    bash "$BIN/bee-nextcloud-sync.sh"
  kill "$srv_pid"
  assert_eq $'/remote.php/webdav/Games\n/remote.php/webdav/Games/bee' "$(cat "$tmp/mkcol" 2>/dev/null)" \
    "MKCOL each segment of /Games/bee, parent first"
  assert_file "$tmp/sync/.bee-synced-once" "sync still runs after creating the folder"
}

# ---------------------------------------------------------------- tests go here

# ---------------------------------------------------------------- runner
if [[ $# -gt 0 ]]; then
  tests=("$@")
else
  mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_')
fi
for t in "${tests[@]}"; do run_test "$t"; done
echo "---- ${#tests[@]} tests, $BEE_FAILS failed"
[[ $BEE_FAILS -eq 0 ]]
