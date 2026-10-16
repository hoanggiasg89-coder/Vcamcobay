#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/build-and-push.sh --branch <feature-branch> --message <commit-message> -- <path> [<path> ...]

The script validates the Theos project, runs `make clean package`, validates the
resulting .deb, stages only the paths listed after `--`, commits, then pushes the
feature branch to origin. It never force-pushes and refuses main/master.

Required: git, make, dpkg-deb, THEOS set to an installed Theos directory,
canonical project files (Makefile, Tweak.x, and control or DEBIAN/control),
and working GitHub credentials for `git push`.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

BRANCH=""
MESSAGE=""
PATHS=()

while (($#)); do
  case "$1" in
    --branch)
      (($# >= 2)) || { usage >&2; exit 2; }
      BRANCH="$2"
      shift 2
      ;;
    --message)
      (($# >= 2)) || { usage >&2; exit 2; }
      MESSAGE="$2"
      shift 2
      ;;
    --)
      shift
      PATHS=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$BRANCH" ]] || { usage >&2; fail "--branch is required"; }
[[ -n "$MESSAGE" ]] || { usage >&2; fail "--message is required"; }
((${#PATHS[@]} > 0)) || { usage >&2; fail "provide explicit paths after --; the script will not stage everything"; }
[[ "$BRANCH" != "main" && "$BRANCH" != "master" ]] || fail "refusing to push directly to $BRANCH; use a feature branch"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "run inside a Git checkout"
cd "$ROOT"

git check-ref-format --branch "$BRANCH" >/dev/null || fail "invalid branch name: $BRANCH"
command -v make >/dev/null || fail "make is required"
command -v dpkg-deb >/dev/null || fail "dpkg-deb is required"

# Stop before building if this checkout is a source archive/stub rather than a
# canonical Theos project. Do not silently rename .txt files or invent inputs.
[[ -f Makefile ]] || fail "missing Makefile (repository currently has Makefile.txt)"
[[ -f Tweak.x || -f Tweak.xm ]] || fail "missing Tweak.x/Tweak.xm (repository currently has Tweak.x.txt)"
[[ -f control || -f DEBIAN/control ]] || fail "missing control metadata (repository currently has DEBIAN/control.txt)"
[[ -n "${THEOS:-}" && -d "$THEOS" ]] || fail "THEOS must point to an installed Theos directory"

ORIGIN="$(git remote get-url origin 2>/dev/null)" || fail "no origin remote configured"
[[ "$ORIGIN" == *github.com* ]] || fail "origin is not a GitHub URL"

# Do not build while a listed path is outside the checkout or points at .git.
for path in "${PATHS[@]}"; do
  [[ -n "$path" && "$path" != "." && "$path" != ".." && "$path" != /* ]] || fail "unsafe/ambiguous staging path: $path"
  case "/$path/" in
    */.git/*) fail "refusing to stage .git contents" ;;
  esac
done

printf '%s\n' "Building package in $ROOT"
printf '%s\n' "Using THEOS=$THEOS"
make clean package

shopt -s nullglob
DEBS=(packages/*.deb)
((${#DEBS[@]} > 0)) || fail "build completed without producing packages/*.deb"
for deb in "${DEBS[@]}"; do
  dpkg-deb --info "$deb" >/dev/null || fail "invalid Debian package: $deb"
done

CURRENT_BRANCH="$(git branch --show-current)"
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    fail "branch $BRANCH already exists locally; check it out and rerun"
  fi
  git switch -c "$BRANCH"
fi

git add -- "${PATHS[@]}"
git diff --cached --check || fail "staged diff has whitespace errors"
git diff --cached --quiet && fail "none of the explicitly listed paths has staged changes"

git commit -m "$MESSAGE"
git push --set-upstream origin "$BRANCH"
printf '%s\n' "Build, commit, and push succeeded for branch $BRANCH."
printf '%s\n' "Built package(s): ${DEBS[*]}"
