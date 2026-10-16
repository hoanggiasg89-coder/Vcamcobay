#!/usr/bin/env bash
set -Eeuo pipefail

# Sources checked when preparing this installer:
# Linux install guide: https://theos.dev/docs/installation-linux
# Official installer pinned to commit:
# https://raw.githubusercontent.com/theos/theos/304e0799973e8145f32e4ca2de6c747a84b758ce/bin/install-theos
# Official SDK installer source (called by upstream install-theos):
# https://raw.githubusercontent.com/theos/theos/304e0799973e8145f32e4ca2de6c747a84b758ce/bin/install-sdk
# Patched iOS SDK repository and instructions: https://github.com/theos/sdks

THEOS_INSTALLER_COMMIT="304e0799973e8145f32e4ca2de6c747a84b758ce"
THEOS_INSTALLER_URL="https://raw.githubusercontent.com/theos/theos/${THEOS_INSTALLER_COMMIT}/bin/install-theos"

usage() {
  cat <<'EOF'
Usage:
  scripts/install-theos-environment.sh [--dry-run] [--skip-build-test]

Default action installs Theos' Linux dependencies, non-Swift iOS toolchain,
Theos, and the latest iPhoneOS SDK available through Theos' official SDK
installer. It then runs scripts/test-build.sh to test `make package` without
installing the tweak. Pass --skip-build-test to install only.

Run as a normal user with sudo access; do not run this script as root.
Supports Debian/Ubuntu with apt-get on Linux x86_64 or aarch64.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

DRY_RUN=0
SKIP_BUILD_TEST=0
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --skip-build-test) SKIP_BUILD_TEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; fail "unknown argument: $1" ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$ROOT/Makefile" && -f "$ROOT/Tweak.x" && -f "$ROOT/control" ]] || \
  fail "canonical Theos project files are missing; run scripts/fix-project-structure.sh --apply first"

[[ "$(uname -s)" == "Linux" ]] || fail "this installer targets Linux only"
[[ -x "$(command -v apt-get || true)" ]] || fail "apt-get is required (Debian/Ubuntu only)"
[[ -x "$(command -v sudo || true)" ]] || fail "sudo is required; install it and rerun as a normal user"
[[ "$EUID" -ne 0 ]] || fail "Theos must be installed as a normal user, not root; rerun without sudo"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|aarch64) ;;
  *) fail "upstream Theos Linux toolchain does not support this architecture here: $ARCH" ;;
esac

THEOS_DIR="${THEOS:-$HOME/theos}"
[[ "$THEOS_DIR" == /* ]] || fail "THEOS must be an absolute path; got: $THEOS_DIR"
[[ "$THEOS_DIR" != "/" && "$THEOS_DIR" != "$HOME" ]] || fail "unsafe THEOS directory: $THEOS_DIR"
[[ "$THEOS_DIR" != *$'\n'* ]] || fail "THEOS path cannot contain a newline"

if [[ -e "$THEOS_DIR" && ! -d "$THEOS_DIR/.git" && ! -f "$THEOS_DIR/bin/install-sdk" ]]; then
  if [[ ! -d "$THEOS_DIR" || -n "$(ls -A "$THEOS_DIR" 2>/dev/null || true)" ]]; then
    fail "THEOS path exists but does not look like a Theos checkout; refusing to overwrite it: $THEOS_DIR"
  fi
fi

if ((DRY_RUN)); then
  cat <<EOF
DRY RUN — no packages or files changed.
OS:              Debian/Ubuntu Linux
Architecture:    $ARCH
THEOS directory: $THEOS_DIR
Installer:       $THEOS_INSTALLER_URL
Actions:
  1. Install prerequisites with apt-get (using sudo).
  2. Run the official Theos installer with CI=1 and the non-Swift toolchain.
  3. Verify an iPhoneOS SDK is present under \$THEOS/sdks.
  4. Persist THEOS in ~/.bashrc and ~/.profile.
EOF
  if ((SKIP_BUILD_TEST)); then
    echo '  5. Skip project build test.'
  else
    echo '  5. Run scripts/test-build.sh (make package + dpkg-deb validation; no install).'
  fi
  exit 0
fi

if ! sudo -n true 2>/dev/null; then
  fail "sudo requires interactive authentication; grant non-interactive sudo access, then rerun (do not put a password in this script)"
fi

LOG_DIR="$HOME/.cache/vcamcobay-theos"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vcamcobay-theos-install.XXXXXX")"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

printf 'Log file: %s\n' "$LOG_FILE"
printf '%s\n' 'Installing base download/archive prerequisites...'
if ! { sudo apt-get update && sudo apt-get install -y bash curl ca-certificates xz-utils git; } 2>&1 | tee -a "$LOG_FILE"; then
  fail "apt prerequisite installation failed; see $LOG_FILE"
fi

INSTALLER="$TMP_DIR/install-theos"
if ! curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$THEOS_INSTALLER_URL" -o "$INSTALLER"; then
  fail "could not download the pinned official Theos installer"
fi
bash -n "$INSTALLER" || fail "downloaded Theos installer failed shell syntax validation"
grep -q 'Theos Installer' "$INSTALLER" || fail "downloaded file did not match the expected Theos installer"
grep -q 'get_sdks' "$INSTALLER" || fail "installer does not contain the expected SDK setup path"

mkdir -p "$(dirname "$THEOS_DIR")"
export THEOS="$THEOS_DIR"
export CI=1
printf '%s\n' 'Running official Theos installer as the current non-root user...'
if ! bash "$INSTALLER" 2>&1 | tee -a "$LOG_FILE"; then
  fail "Theos installer failed; see $LOG_FILE"
fi

# The official installer installs the latest iPhoneOS SDK when none is present.
# Check specifically for iOS SDKs instead of accepting a tvOS SDK as sufficient.
shopt -s nullglob
IOS_SDKS=("$THEOS_DIR"/sdks/iPhoneOS*.sdk)
if ((${#IOS_SDKS[@]} == 0)); then
  [[ -x "$THEOS_DIR/bin/install-sdk" ]] || fail "Theos install-sdk helper is missing; see $LOG_FILE"
  printf '%s\n' 'No iPhoneOS SDK found; invoking Theos SDK installer for latest iOS SDK...'
  if ! "$THEOS_DIR/bin/install-sdk" latest 2>&1 | tee -a "$LOG_FILE"; then
    fail "iOS SDK installation failed; see $LOG_FILE"
  fi
  IOS_SDKS=("$THEOS_DIR"/sdks/iPhoneOS*.sdk)
fi
((${#IOS_SDKS[@]} > 0)) || fail "Theos setup finished without an iPhoneOS SDK; see $LOG_FILE"
[[ -d "$THEOS_DIR/toolchain/linux/iphone" ]] || fail "Linux iOS toolchain directory is missing; see $LOG_FILE"

# Keep the environment available in new Bash sessions without duplicating lines.
printf -v THEOS_SHELL_VALUE '%q' "$THEOS_DIR"
THEOS_LINE="export THEOS=$THEOS_SHELL_VALUE"
for startup_file in "$HOME/.bashrc" "$HOME/.profile"; do
  touch "$startup_file"
  if ! grep -Fqx "$THEOS_LINE" "$startup_file"; then
    printf '\n# Theos environment (managed by Vcamcobay installer)\n%s\n' "$THEOS_LINE" >> "$startup_file"
  fi
done

printf '\nTheos environment verified. Installed iOS SDK(s):\n'
printf '  %s\n' "${IOS_SDKS[@]}"
printf 'THEOS=%s\n' "$THEOS_DIR"
printf '%s\n' 'Open a new shell or run: source ~/.bashrc'
printf 'Install log: %s\n' "$LOG_FILE"

if ((!SKIP_BUILD_TEST)); then
  printf '%s\n' 'Running the project build test; this runs make package only and does not install or respring...'
  if ! THEOS="$THEOS_DIR" "$ROOT/scripts/test-build.sh"; then
    printf '%s\n' 'Theos/toolchain setup is present, but the Vcamcobay project build test failed. Review the build log and source errors above.' >&2
    exit 20
  fi
fi

printf '%s\n' 'Theos installation and requested checks completed.'
