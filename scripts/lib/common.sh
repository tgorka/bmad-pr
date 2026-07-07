# shellcheck shell=bash
# Shared primitives. Source, don't execute.

# Exit-code contract (architecture R9).
# shellcheck disable=SC2034  # consumed by sourcing scripts
EX_OK=0
EX_FAIL=1
EX_REFUSE=2
EX_FINDINGS=3
EX_CHECKS_FAILED=4
EX_TIMEOUT=5
EX_NO_REVIEWER=6

log() { printf 'bmad-pr: %s\n' "$*" >&2; }
warn() { printf 'bmad-pr: warning: %s\n' "$*" >&2; }

# Unexpected failure (exit 1): environment/tool errors, bugs.
die() {
  printf 'bmad-pr: error: %s\n' "$*" >&2
  exit "$EX_FAIL"
}

# Refusal (exit 2): a precondition is not met; the message says how to proceed.
refuse() {
  printf 'bmad-pr: refuse: %s\n' "$*" >&2
  exit "$EX_REFUSE"
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

epoch() { date +%s; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || refuse "required tool not found on PATH: $1"
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || refuse "not inside a git repository"
}

current_branch() { git rev-parse --abbrev-ref HEAD; }

head_sha() { git rev-parse HEAD; }

# Sanitize a story key for use as a filename: anything outside [A-Za-z0-9._-]
# becomes '-'. Keys like "3.2" or "quick-fix-login" pass through unchanged.
sanitize_key() {
  local key=$1
  printf '%s' "${key//[^A-Za-z0-9._-]/-}"
}

# remote_slug <remote> → owner/repo parsed from the remote URL (rc 1 when
# the remote is absent or the URL is not a forge-style URL).
remote_slug() {
  local url
  url="$(git remote get-url "$1" 2>/dev/null)" || return 1
  url="${url%.git}"
  case "$url" in
    git@*:*)
      url="${url#git@}"
      url="${url#*:}"
      ;;
    ssh://git@*)
      url="${url#ssh://git@}"
      url="${url#*/}"
      ;;
    http://* | https://*)
      url="${url#*://}"
      url="${url#*/}"
      ;;
    *) return 1 ;;
  esac
  [[ "$url" == */* ]] || return 1
  printf '%s\n' "$url"
}
