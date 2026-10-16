#!/usr/bin/env bash
set -Eeuo pipefail

# Canonical Theos project layout references:
# https://orion.theos.dev/versions/1.0.0/getting-started
# https://theos.dev/docs/Variables.html
# The Theos project root uses Makefile, tweak source (e.g. Tweak.x), and control.

usage() {
  cat <<'EOF'
Usage:
  scripts/fix-project-structure.sh [--dry-run | --apply]

Default: dry-run only. Pass --apply to perform collision-safe renames.

Renames when the source exists and the destination does not:
  Makefile.txt             -> Makefile
  Tweak.x.txt              -> Tweak.x
  DEBIAN/control.txt       -> control   (Theos project-root package metadata)
  .gitignore.txt           -> .gitignore
  CHANGELOG.md.txt         -> CHANGELOG.md

The script does not overwrite existing files, rename installer scripts, alter
resource contents/extensions, rewrite the GitHub Actions workflow, build, commit,
or push.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

MODE="dry-run"
(($# <= 1)) || { usage >&2; fail "pass only one mode flag"; }
case "${1:-}" in
  "") ;;
  --dry-run) MODE="dry-run" ;;
  --apply) MODE="apply" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; fail "unknown argument: $1" ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
git rev-parse --show-toplevel >/dev/null 2>&1 || fail "script must be inside the Vcamcobay Git checkout"

# Map: current path -> intended canonical path. Keep in sync with README/Makefile.
SOURCES=(
  "Makefile.txt"
  "Tweak.x.txt"
  "DEBIAN/control.txt"
  ".gitignore.txt"
  "CHANGELOG.md.txt"
)
DESTINATIONS=(
  "Makefile"
  "Tweak.x"
  "control"
  ".gitignore"
  "CHANGELOG.md"
)

PLAN_SOURCES=()
PLAN_DESTINATIONS=()
CONFLICTS=()

for i in "${!SOURCES[@]}"; do
  src="${SOURCES[$i]}"
  dst="${DESTINATIONS[$i]}"
  if [[ -e "$dst" || -L "$dst" ]]; then
    if [[ -e "$src" || -L "$src" ]]; then
      CONFLICTS+=("$src -> $dst (both exist; neither will be changed)")
    else
      printf 'Already canonical: %s\n' "$dst"
    fi
    continue
  fi
  if [[ -e "$src" || -L "$src" ]]; then
    [[ -f "$src" && ! -L "$src" ]] || fail "refusing to rename non-regular file or symlink: $src"
    PLAN_SOURCES+=("$src")
    PLAN_DESTINATIONS+=("$dst")
  else
    printf 'Not present, skip: %s\n' "$src"
  fi
done

if ((${#CONFLICTS[@]})); then
  printf '%s\n' 'Conflicts found; no changes will be made:' >&2
  printf '  %s\n' "${CONFLICTS[@]}" >&2
  exit 1
fi

if ((${#PLAN_SOURCES[@]} == 0)); then
  printf '%s\n' 'No renames required.'
  exit 0
fi

if [[ "$MODE" == "dry-run" ]]; then
  printf '%s\n' 'DRY RUN — no files changed. Planned renames:'
  for i in "${!PLAN_SOURCES[@]}"; do
    printf '  %s -> %s\n' "${PLAN_SOURCES[$i]}" "${PLAN_DESTINATIONS[$i]}"
  done
else
  printf '%s\n' 'Applying file renames:'
  MOVED_SOURCES=()
  MOVED_DESTINATIONS=()
  for i in "${!PLAN_SOURCES[@]}"; do
    src="${PLAN_SOURCES[$i]}"
    dst="${PLAN_DESTINATIONS[$i]}"
    # -n prevents an unexpected destination from being overwritten if it
    # appears after preflight; verify the source disappeared before recording.
    if ! mv -n "$src" "$dst"; then
      for ((j=${#MOVED_SOURCES[@]}-1; j>=0; j--)); do
        mv -n "${MOVED_DESTINATIONS[$j]}" "${MOVED_SOURCES[$j]}" || true
      done
      fail "rename failed for $src -> $dst; attempted to roll back earlier renames"
    fi
    if [[ -e "$src" || -L "$src" ]]; then
      for ((j=${#MOVED_SOURCES[@]}-1; j>=0; j--)); do
        mv -n "${MOVED_DESTINATIONS[$j]}" "${MOVED_SOURCES[$j]}" || true
      done
      fail "rename refused for $src -> $dst; attempted to roll back earlier renames"
    fi
    MOVED_SOURCES+=("$src")
    MOVED_DESTINATIONS+=("$dst")
    printf '  renamed %s -> %s\n' "$src" "$dst"
  done
  printf '%s\n' 'Renames completed. No source contents were edited.'
fi

# Warn about known issues that are intentionally outside a filename-only fix.
if [[ -f "DEBIAN/postinst.txt" && -f "DEBIAN/postinst" ]]; then
  printf '%s\n' 'WARNING: left DEBIAN/postinst.txt untouched; DEBIAN/postinst already exists, and the .txt variant contains SpringBoard restart commands.'
fi
if [[ -f "Resources/vcamcobay_logo.png.JPG" ]]; then
  printf '%s\n' 'WARNING: left Resources/vcamcobay_logo.png.JPG unchanged; it is JPEG content, not a PNG. Renaming the extension alone would be incorrect.'
fi
if [[ -f ".github/workflows/build.yml" ]]; then
  printf '%s\n' 'WARNING: build.yml is not rewritten by this script; its Theos setup must be repaired separately before CI can build.'
fi
