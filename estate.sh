#!/usr/bin/env bash
# estate.sh — the whole estate (three workspaces, ~27 repositories) from one command.
#
#   ./estate.sh clone  [--root DIR] [--dry-run]   clone every workspace and sub-repository that is missing
#   ./estate.sh pull   [--root DIR]               fast-forward every clean repository (dirty ones are skipped and listed)
#   ./estate.sh status [--root DIR] [--fetch]     one line per repository: branch, ahead/behind, dirty files
#   ./estate.sh check  [--root DIR]               manifests vs disk vs .gitignore — the map must match the territory
#
# The map lives in estate/*.repos (data, not code): workspaces.repos names the three sibling
# workspaces, <workspace>.repos names each one's sub-repositories as "<directory> <git url>".
# The estate root defaults to the parent of the directory holding this script (this workspace
# is cloned as <root>/shared). Every command is idempotent: run it again, nothing breaks.
#
# Private repositories clone over HTTPS only with credentials. If the GitHub CLI is installed
# and signed in, `gh auth setup-git` is run once so git borrows its token; otherwise you are told.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$HERE/estate"
ROOT="$(dirname "$HERE")"
DRY_RUN=0
FETCH=0

usage() { sed -n '2,15p' "$0"; exit "${1:-0}"; }

COMMAND="${1:-}"; [ -n "$COMMAND" ] || usage 1; shift
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$(mkdir -p "$2" && cd "$2" && pwd)"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --fetch) FETCH=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

# --- manifest access -------------------------------------------------------------------------

# entries FILE — prints "<dir> <url>" per line, comments and blanks dropped
entries() { grep -vE '^\s*(#|$)' "$1" | awk '{print $1, $2}'; }

workspaces() { entries "$MANIFESTS/workspaces.repos"; }

# every repository of the estate as "<path relative to root> <url> <owning workspace or ->"
all_repos() {
  while read -r ws url; do
    echo "$ws $url -"
    [ -f "$MANIFESTS/$ws.repos" ] || { echo "no manifest for workspace '$ws': $MANIFESTS/$ws.repos" >&2; exit 1; }
    while read -r dir sub_url; do echo "$ws/$dir $sub_url $ws"; done < <(entries "$MANIFESTS/$ws.repos")
  done < <(workspaces)
}

# --- helpers ---------------------------------------------------------------------------------

run() { if [ "$DRY_RUN" = 1 ]; then echo "  would: $*"; else "$@"; fi; }

# ensure_credentials — private repositories need a token; borrow the GitHub CLI's if it has one
ensure_credentials() {
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    run gh auth setup-git >/dev/null
    echo "github: signed in via gh; git will use its credentials for private repositories"
  else
    cat <<'MSG'
github: NOT signed in via the GitHub CLI. Public repositories will clone; private ones
        (the formula workspace's three repositories) will fail unless git has credentials of its own. Fix: `gh auth login`, then rerun.
MSG
  fi
}

# --- commands --------------------------------------------------------------------------------

cmd_clone() {
  echo "estate root: $ROOT"
  ensure_credentials
  local failed=() cloned=0 present=0
  while read -r path url _; do
    local target="$ROOT/$path"
    if [ -d "$target/.git" ]; then
      present=$((present + 1))
    elif [ -e "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
      echo "SKIP  $path — exists but is not a git repository (not touching it)"
      failed+=("$path (directory in the way)")
    else
      echo "CLONE $path  <-  $url"
      if run git clone --quiet "$url" "$target"; then cloned=$((cloned + 1)); else failed+=("$path"); fi
    fi
  done < <(all_repos)
  echo
  echo "already present: $present   cloned now: $cloned   failed: ${#failed[@]}"
  if [ ${#failed[@]} -gt 0 ]; then
    printf '  FAILED  %s\n' "${failed[@]}"
    exit 1
  fi
  echo "next: cd $ROOT/shared && ./mvnw install   # the kernel first; products consume it from ~/.m2"
}

cmd_pull() {
  local skipped=() failed=()
  while read -r path _ _; do
    local target="$ROOT/$path"
    [ -d "$target/.git" ] || { echo "MISSING $path (run: estate.sh clone)"; skipped+=("$path (missing)"); continue; }
    if [ -n "$(git -C "$target" status --porcelain)" ]; then
      echo "DIRTY   $path — not pulling over uncommitted changes"; skipped+=("$path (dirty)"); continue
    fi
    printf 'PULL    %-40s ' "$path"
    if run git -C "$target" pull --ff-only --quiet; then echo ok; else echo FAILED; failed+=("$path"); fi
  done < <(all_repos)
  [ ${#skipped[@]} -eq 0 ] || { echo; printf 'skipped: %s\n' "${skipped[@]}"; }
  [ ${#failed[@]} -eq 0 ] || { printf 'FAILED:  %s\n' "${failed[@]}"; exit 1; }
}

cmd_status() {
  printf '%-42s %-14s %6s %6s %6s\n' REPOSITORY BRANCH AHEAD BEHIND DIRTY
  local attention=0
  while read -r path _ _; do
    local target="$ROOT/$path"
    if [ ! -d "$target/.git" ]; then printf '%-42s %s\n' "$path" "MISSING"; attention=1; continue; fi
    [ "$FETCH" = 1 ] && git -C "$target" fetch --quiet 2>/dev/null || true
    local branch ahead behind dirty
    branch="$(git -C "$target" branch --show-current 2>/dev/null || echo '?')"
    if git -C "$target" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      ahead="$(git -C "$target" rev-list --count '@{u}..HEAD')"
      behind="$(git -C "$target" rev-list --count 'HEAD..@{u}')"
    else
      ahead='-'; behind='-'
    fi
    dirty="$(git -C "$target" status --porcelain | wc -l)"
    local mark=' '
    if [ "$ahead" != 0 ] || [ "$behind" != 0 ] || [ "$dirty" != 0 ]; then mark='*'; attention=1; fi
    printf '%-42s %-14s %6s %6s %6s %s\n' "$path" "$branch" "$ahead" "$behind" "$dirty" "$mark"
  done < <(all_repos)
  [ "$attention" = 0 ] && echo "everything committed, pushed and present" || echo "* = needs attention"
  [ "$FETCH" = 1 ] || echo "(ahead/behind are against the last fetch; add --fetch to ask the remotes)"
}

cmd_check() {
  local problems=0
  while read -r ws _; do
    local wsdir="$ROOT/$ws" manifest="$MANIFESTS/$ws.repos"
    [ -d "$wsdir" ] || { echo "workspace missing on disk: $ws"; problems=1; continue; }
    # 1. every sub-repository in the manifest must be gitignored by its workspace
    while read -r dir _; do
      if ! git -C "$wsdir" check-ignore -q "$dir" 2>/dev/null; then
        echo "$ws: '$dir' is in $(basename "$manifest") but NOT gitignored by the workspace"; problems=1
      fi
    done < <(entries "$manifest")
    # 2. every git repository on disk under the workspace must be in the manifest
    for d in "$wsdir"/*/; do
      d="${d%/}"; local name; name="$(basename "$d")"
      [ -d "$d/.git" ] || continue
      if ! entries "$manifest" | awk '{print $1}' | grep -qx "$name"; then
        echo "$ws: '$name' is a git repository on disk but NOT in $(basename "$manifest")"; problems=1
      fi
    done
    # 3. every manifest URL must match the clone's origin
    while read -r dir url; do
      [ -d "$wsdir/$dir/.git" ] || continue
      local origin; origin="$(git -C "$wsdir/$dir" remote get-url origin 2>/dev/null || echo '-')"
      if [ "${origin%.git}" != "${url%.git}" ]; then
        echo "$ws/$dir: origin is '$origin', manifest says '$url'"; problems=1
      fi
    done < <(entries "$manifest")
  done < <(workspaces)
  [ "$problems" = 0 ] && echo "map matches territory: $(all_repos | wc -l) repositories" || exit 1
}

case "$COMMAND" in
  clone)  cmd_clone ;;
  pull)   cmd_pull ;;
  status) cmd_status ;;
  check)  cmd_check ;;
  *) echo "unknown command: $COMMAND" >&2; usage 1 ;;
esac
