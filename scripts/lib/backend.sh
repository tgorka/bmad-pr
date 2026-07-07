# shellcheck shell=bash
# Backend selection (R4): gt > gh > git, with explicit override via
# BMAD_PR_TOOL (flag > env > config > auto-detect).
#
# gt only when the repo explicitly opted in (gt init wrote its config) —
# mixing gt and gh mid-stack is unsafe because gt owns branch metadata and
# force-pushes. The gt probe must use --git-common-dir: in a linked worktree
# the config lives in the main repo's .git dir.

backend_detect() {
  case "${BMAD_PR_TOOL:-auto}" in
    gt | gh | git)
      printf '%s\n' "$BMAD_PR_TOOL"
      return 0
      ;;
    auto) ;;
    *) refuse "invalid BMAD_PR_TOOL: '$BMAD_PR_TOOL' (want auto|gt|gh|git)" ;;
  esac

  local url
  url="$(git remote get-url "${BMAD_PR_REMOTE:-origin}" 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    printf 'git\n'
    return 0
  fi
  case "$url" in
    *github.*) ;;
    *)
      # Non-GitHub remote: no gh/gt PR automation available.
      printf 'git\n'
      return 0
      ;;
  esac

  if command -v gt >/dev/null 2>&1; then
    local common
    common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
    if [[ -n "$common" && -f "$common/.graphite_repo_config" ]]; then
      printf 'gt\n'
      return 0
    fi
  fi

  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    printf 'gh\n'
    return 0
  fi

  printf 'git\n'
}

# gh remains the query surface for checks/threads even on the gt path.
backend_query_available() {
  command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
}
