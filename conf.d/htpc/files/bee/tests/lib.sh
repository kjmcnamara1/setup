# shellcheck shell=bash
# Tiny assert helpers shared by test-scripts.sh and check-bee.sh.

BEE_FAILS=0

_pass() { printf 'PASS  %s\n' "$1"; }
_fail() { printf 'FAIL  %s\n' "$1"; BEE_FAILS=$((BEE_FAILS + 1)); }

assert_eq() { # <expected> <actual> <msg>
  if [[ "$1" == "$2" ]]; then _pass "$3"; else _fail "$3 (expected '$1', got '$2')"; fi
}

assert_file() { # <path> [msg]
  if [[ -e "$1" ]]; then _pass "${2:-exists: $1}"; else _fail "${2:-exists: $1}"; fi
}

assert_no_file() { # <path> [msg]
  if [[ ! -e "$1" ]]; then _pass "${2:-absent: $1}"; else _fail "${2:-absent: $1}"; fi
}

assert_contains() { # <file> <text> [msg]
  if [[ -f "$1" ]] && grep -qF -- "$2" "$1"; then _pass "${3:-$1 contains '$2'}"; else _fail "${3:-$1 contains '$2'}"; fi
}

assert_cmd() { # <msg> <cmd...>  — passes when the command succeeds
  local msg="$1"; shift
  if "$@" >/dev/null 2>&1; then _pass "$msg"; else _fail "$msg"; fi
}

assert_symlink_into() { # <link> <dir-prefix>
  local target
  target="$(readlink -f "$1" 2>/dev/null || true)"
  if [[ -L "$1" && "$target" == "$2"* ]]; then _pass "symlink $1 -> $2…"; else _fail "symlink $1 -> $2… (got '${target}')"; fi
}

# run_test <fn>: runs a test function in a subshell with a fresh $tmp.
run_test() {
  local fn="$1" out rc
  tmp="$(mktemp -d)"
  export tmp
  out="$( (set -e; "$fn") 2>&1 )"; rc=$?
  printf '%s\n' "$out" | sed "s/^/  [$fn] /"
  if [[ $rc -ne 0 ]] || grep -q '^FAIL' <<<"$out"; then
    printf 'FAIL  %s\n' "$fn"; BEE_FAILS=$((BEE_FAILS + 1))
  else
    printf 'PASS  %s\n' "$fn"
  fi
  rm -rf "$tmp"
}
