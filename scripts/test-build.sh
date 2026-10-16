#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/test-build.sh

Checks the canonical Theos project files, runs `make package` without installing
anything, writes the package to a temporary directory, and validates it with
dpkg-deb. It does not run `make install`, kill SpringBoard, commit, or push.

Requirements: make, dpkg-deb, and THEOS pointing to an installed Theos tree.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
(($# == 0)) || { usage >&2; echo 'ERROR: no positional arguments accepted' >&2; exit 2; }

fail() {
  printf 'BUILD TEST FAILED: %s\n' "$*" >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
git rev-parse --show-toplevel >/dev/null 2>&1 || fail "script must be inside the Vcamcobay Git checkout"

for file in Makefile Tweak.x control; do
  [[ -f "$file" ]] || fail "missing canonical project file: $file"
done
command -v make >/dev/null || fail "make is not installed"
command -v dpkg-deb >/dev/null || fail "dpkg-deb is not installed"

if [[ -z "${THEOS:-}" ]]; then
  for candidate in "$HOME/theos" /opt/theos; do
    if [[ -d "$candidate/makefiles" ]]; then
      export THEOS="$candidate"
      break
    fi
  done
fi
[[ -n "${THEOS:-}" && -d "$THEOS/makefiles" ]] || fail "Theos is not installed or THEOS is unset; install Theos and export THEOS=/path/to/theos"

if ! grep -Eq '^[[:space:]]*Vcamcobay_FILES[[:space:]]*=[[:space:]]*Tweak\.x[[:space:]]*$' Makefile; then
  fail "Makefile does not list the renamed Tweak.x as the tweak source"
fi

OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vcamcobay-package-test.XXXXXX")"
LOG_FILE="${TMPDIR:-/tmp}/vcamcobay-make-package-$(date +%Y%m%d-%H%M%S)-$$.log"
cleanup() {
  rm -rf "$OUT_DIR"
}
trap cleanup EXIT

printf 'Project: %s\n' "$ROOT"
printf 'Theos:   %s\n' "$THEOS"
printf 'Log:     %s\n' "$LOG_FILE"
printf '%s\n' 'Running make package (no install step)...'

if ! THEOS_PACKAGE_DIR="$OUT_DIR" make package 2>&1 | tee "$LOG_FILE"; then
  printf 'Build failed. Full log: %s\n' "$LOG_FILE" >&2
  exit 1
fi

shopt -s nullglob
PACKAGES=("$OUT_DIR"/*.deb)
((${#PACKAGES[@]} > 0)) || fail "make package returned success but produced no .deb in $OUT_DIR"

for package in "${PACKAGES[@]}"; do
  dpkg-deb --info "$package" >/dev/null || fail "dpkg-deb rejected package metadata: $package"
  dpkg-deb --contents "$package" >/dev/null || fail "dpkg-deb rejected package contents: $package"
  printf 'PACKAGE OK: %s (%s bytes)\n' "$(basename "$package")" "$(wc -c < "$package" | tr -d ' ')"
done

printf '%s\n' 'BUILD TEST PASSED: package built and passed dpkg-deb metadata/content checks.'
printf '%s\n' 'This validates packaging only; it does not prove camera injection or runtime stability.'
printf 'Build log: %s\n' "$LOG_FILE"
