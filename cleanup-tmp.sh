#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="${TMP_DIR:-/tmp}"
MIN_AGE_DAYS="${MIN_AGE_DAYS:-2}"
MODE="dry-run"

usage() {
  cat <<USAGE
Usage: $0 [--apply] [--age DAYS]

Default behavior is DRY RUN: discover cleanup candidates only.

Options:
  --apply       Delete candidates that pass all safety checks.
  --age DAYS    Minimum age in days since any entry in the tree was modified
                (default: ${MIN_AGE_DAYS}).
  -h, --help    Show this help.

Environment:
  TMP_DIR                    Directory to inspect (default: /tmp).
  MIN_AGE_DAYS               Minimum age in days (default: 2).
  TMP_DIR_ALLOW_NONSTANDARD  Set to 1 to allow a TMP_DIR other than /tmp.
  ALLOW_ROOT                 Set to 1 to allow deletion while running as root.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      MODE="apply"
      shift
      ;;
    --age)
      [[ $# -ge 2 ]] || { echo "ERROR: --age requires a value" >&2; exit 2; }
      MIN_AGE_DAYS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$MIN_AGE_DAYS" =~ ^[1-9][0-9]*$ ]] || {
  echo "ERROR: age must be an integer >= 1" >&2
  exit 2
}
[[ -d "$TMP_DIR" ]] || { echo "ERROR: $TMP_DIR is not a directory" >&2; exit 1; }

TMP_REAL="$(readlink -f -- "$TMP_DIR")"
[[ "$TMP_REAL" == "/tmp" || "${TMP_DIR_ALLOW_NONSTANDARD:-0}" == "1" ]] || {
  echo "ERROR: refusing to operate on $TMP_REAL. Set TMP_DIR_ALLOW_NONSTANDARD=1 only if intentional." >&2
  exit 1
}

have_lsof=0
if command -v lsof >/dev/null 2>&1; then
  have_lsof=1
fi

if [[ "$MODE" == "apply" && $have_lsof -eq 0 ]]; then
  echo "ERROR: --apply requires lsof so open-file checks can be performed." >&2
  exit 1
fi

if [[ "$MODE" == "apply" && $EUID -eq 0 && "${ALLOW_ROOT:-0}" != "1" ]]; then
  echo "ERROR: refusing --apply as root. Set ALLOW_ROOT=1 only if intentional." >&2
  exit 1
fi

is_protected_name() {
  local base="$1"
  case "$base" in
    .|..|.X11-unix|.ICE-unix|.XIM-unix|.font-unix|.Test-unix|systemd-private-*|snap-private-tmp|snap.*|ssh-*|tmux-*)
      return 0
      ;;
  esac
  return 1
}

is_open_or_busy() {
  local path="$1"

  if [[ $have_lsof -eq 0 ]]; then
    return 2
  fi

  if [[ -d "$path" ]]; then
    lsof +D "$path" >/dev/null 2>&1 && return 0
  else
    lsof -- "$path" >/dev/null 2>&1 && return 0
  fi
  return 1
}

# Return values:
#   0: the path itself or a descendant is recent
#   1: the whole tree is old enough
#   2: the tree could not be inspected completely
has_recent_content() {
  local path="$1"
  local min_age_minutes=$((MIN_AGE_DAYS * 24 * 60))
  local recent

  if ! recent="$(find -P "$path" -mmin "-${min_age_minutes}" -print -quit 2>/dev/null)"; then
    return 2
  fi

  [[ -n "$recent" ]]
}

human_size() {
  du -sh -- "$1" 2>/dev/null | awk 'NR == 1 { print $1; exit }'
}

format_bytes() {
  local bytes="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$bytes"
  else
    printf '%s bytes\n' "$bytes"
  fi
}

printf 'Mode: %s\n' "$MODE"
printf 'Directory: %s\n' "$TMP_REAL"
printf 'Minimum age: %s day(s) across entire tree\n' "$MIN_AGE_DAYS"
printf 'lsof available: %s\n\n' "$([[ $have_lsof -eq 1 ]] && echo yes || echo no)"

candidate_count=0
candidate_bytes=0
skipped_count=0
removed_count=0
removed_bytes=0
delete_failures=0

# Inspect direct children only. A whole child is eligible only when the child and
# every descendant are old enough, the tree can be scanned, and nothing is open.
while IFS= read -r -d '' path; do
  base="$(basename -- "$path")"

  if is_protected_name "$base"; then
    printf 'SKIP protected:  %s\n' "$path"
    ((skipped_count+=1))
    continue
  fi

  if [[ ! -f "$path" && ! -d "$path" && ! -L "$path" ]]; then
    printf 'SKIP special:    %s\n' "$path"
    ((skipped_count+=1))
    continue
  fi

  if has_recent_content "$path"; then
    printf 'SKIP recent:     %s\n' "$path"
    ((skipped_count+=1))
    continue
  else
    age_status=$?
    if [[ $age_status -eq 2 ]]; then
      printf 'SKIP scan error: %s\n' "$path"
      ((skipped_count+=1))
      continue
    fi
  fi

  if is_open_or_busy "$path"; then
    printf 'SKIP busy/open:  %s\n' "$path"
    ((skipped_count+=1))
    continue
  else
    open_status=$?
    if [[ $open_status -eq 2 ]]; then
      printf 'SKIP no lsof:    %s\n' "$path"
      ((skipped_count+=1))
      continue
    fi
  fi

  size_bytes="$(du -sb -- "$path" 2>/dev/null | awk 'NR == 1 { print $1; exit }' || true)"
  [[ "$size_bytes" =~ ^[0-9]+$ ]] || size_bytes=0
  size_human="$(human_size "$path" || true)"
  [[ -n "$size_human" ]] || size_human="?"

  printf 'CANDIDATE %-8s %s\n' "$size_human" "$path"
  ((candidate_count+=1))
  ((candidate_bytes+=size_bytes))

  if [[ "$MODE" == "apply" ]]; then
    # Re-check immediately before deletion to narrow the discovery/delete race.
    if has_recent_content "$path"; then
      printf 'SKIP became recent: %s\n' "$path"
      ((skipped_count+=1))
      continue
    else
      age_status=$?
      if [[ $age_status -eq 2 ]]; then
        printf 'SKIP scan error:    %s\n' "$path"
        ((skipped_count+=1))
        continue
      fi
    fi

    if is_open_or_busy "$path"; then
      printf 'SKIP became busy:   %s\n' "$path"
      ((skipped_count+=1))
      continue
    fi

    if rm -rf --one-file-system -- "$path"; then
      printf 'REMOVED: %s\n' "$path"
      ((removed_count+=1))
      ((removed_bytes+=size_bytes))
    else
      printf 'WARN delete failed: %s\n' "$path" >&2
      ((delete_failures+=1))
    fi
  fi
done < <(find -P "$TMP_REAL" -mindepth 1 -maxdepth 1 -print0)

printf '\nSummary\n'
printf '  candidates: %d\n' "$candidate_count"
printf '  estimated candidate bytes: %s\n' "$(format_bytes "$candidate_bytes")"
printf '  skipped by safety checks: %d\n' "$skipped_count"
printf '  removed: %d\n' "$removed_count"
printf '  estimated removed bytes: %s\n' "$(format_bytes "$removed_bytes")"
printf '  delete failures: %d\n' "$delete_failures"

if [[ "$MODE" == "dry-run" ]]; then
  printf '\nNothing was deleted. Review the candidates above.\n'
  printf 'To actually delete them later: %s --apply\n' "$0"
fi
