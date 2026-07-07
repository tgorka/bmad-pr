# shellcheck shell=bash
# Git-safety preflight (R10) — CH1/CH2/CH3/CH5 ported from v0 (tag v0-ts-cli).
# Order matters: CH1 first (others give weird signals on detached HEAD), CH2
# before reading porcelain, CH3 local-only, CH5 last (network round-trip).
#
# Contract:
# - preflight_run <auto_fix:true|false> <dry_run:true|false>
# - Auto-fix is bounded: one attempt per check per invocation, never touches
#   non-BMAD files, never force-pushes, never resolves conflicts.
# - Dry-run never mutates: a failing check refuses, describing the would-be fix.

preflight_run() {
  local auto_fix=$1 dry_run=$2
  local check
  for check in ch1 ch2 ch3 ch5; do
    "preflight_$check" && continue
    if [[ "$dry_run" == true ]]; then
      refuse "$PREFLIGHT_MSG (dry-run: would ${PREFLIGHT_FIX_DESC:-refuse; no auto-fix for this})"
    fi
    if [[ "$auto_fix" == true && -n "${PREFLIGHT_FIX_FN:-}" ]]; then
      log "auto-fix ($check): ${PREFLIGHT_FIX_DESC}"
      "$PREFLIGHT_FIX_FN" || refuse "$PREFLIGHT_MSG — auto-fix failed; resolve manually"
      "preflight_$check" || refuse "$PREFLIGHT_MSG — auto-fix did not resolve it"
      if [[ "$check" == ch5 ]]; then
        # A rebase pulled in by CH5 may leave conflict state behind.
        preflight_ch2 || refuse "$PREFLIGHT_MSG — CH5 auto-fix produced conflicts; aborted"
      fi
    else
      refuse "$PREFLIGHT_MSG${PREFLIGHT_FIX_HINT:+ $PREFLIGHT_FIX_HINT}"
    fi
  done
  return 0
}

# CH1 — detached HEAD.
preflight_ch1() {
  PREFLIGHT_MSG='' PREFLIGHT_FIX_HINT='' PREFLIGHT_FIX_DESC='' PREFLIGHT_FIX_FN=''
  [[ "$(git rev-parse --abbrev-ref HEAD)" != "HEAD" ]] && return 0
  PREFLIGHT_MSG="detached HEAD"
  PREFLIGHT_FIX_HINT="Try: --auto-fix to branch from the current commit."
  PREFLIGHT_FIX_DESC="create branch bmad-pr/<short-sha>-<epoch> at current HEAD"
  PREFLIGHT_FIX_FN=preflight_ch1_fix
  return 1
}

preflight_ch1_fix() {
  git switch -c "bmad-pr/$(git rev-parse --short HEAD)-$(epoch)"
}

# CH2 — mid-rebase / mid-merge. Refuse hard; never auto-fix.
preflight_ch2() {
  PREFLIGHT_MSG='' PREFLIGHT_FIX_HINT='' PREFLIGHT_FIX_DESC='' PREFLIGHT_FIX_FN=''
  local git_dir
  git_dir="$(git rev-parse --git-dir)"
  if [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]]; then
    PREFLIGHT_MSG="rebase in progress"
    PREFLIGHT_FIX_HINT="Run: git rebase --continue (or --abort), then retry."
    return 1
  fi
  if [[ -f "$git_dir/MERGE_HEAD" ]]; then
    PREFLIGHT_MSG="merge in progress"
    PREFLIGHT_FIX_HINT="Run: git merge --continue (or --abort), then retry."
    return 1
  fi
  return 0
}

# CH3 — unstaged changes outside the BMAD scope ($BMAD_PR_STAGE_GLOB).
# Entries counted: untracked (??) or worktree-side dirty (Y column not space).
# Staged-only entries pass. Auto-fix stages only scope paths; residue refuses.
preflight_ch3() {
  PREFLIGHT_MSG='' PREFLIGHT_FIX_HINT='' PREFLIGHT_FIX_DESC='' PREFLIGHT_FIX_FN=''
  local scope="${BMAD_PR_STAGE_GLOB:-_bmad-output/}"
  local entry xy path orig offending=""
  # Porcelain v1 -z: "XY <path>\0" with a second NUL field (original path)
  # for renames/copies.
  while IFS= read -r -d '' entry; do
    xy="${entry:0:2}"
    path="${entry:3}"
    orig=""
    if [[ "$xy" == R* || "$xy" == C* ]]; then
      IFS= read -r -d '' orig || true
    fi
    [[ "$xy" == '??' || "${xy:1:1}" != ' ' ]] || continue
    if [[ "$path" != "$scope"* ]]; then
      offending="${offending:-$path}"
    elif [[ -n "$orig" && "$orig" != "$scope"* ]]; then
      # A rename from outside the scope into it still touches outside state.
      offending="${offending:-$orig}"
    fi
  done < <(git status --porcelain -z)
  [[ -z "$offending" ]] && return 0
  PREFLIGHT_MSG="unstaged changes outside $scope (e.g. $offending)"
  PREFLIGHT_FIX_HINT="Commit or stash them, or: --auto-fix to stage only $scope paths."
  PREFLIGHT_FIX_DESC="git add -- $scope (never -A; non-BMAD paths are left alone)"
  PREFLIGHT_FIX_FN=preflight_ch3_fix
  return 1
}

preflight_ch3_fix() {
  local scope="${BMAD_PR_STAGE_GLOB:-_bmad-output/}"
  # Guard: git add errors on a pathspec that matches nothing.
  if [[ -e "$(repo_root)/$scope" ]]; then
    git add -- "$scope"
  fi
}

# CH5 — upstream has commits we don't (force-push race / concurrent amend).
preflight_ch5() {
  PREFLIGHT_MSG='' PREFLIGHT_FIX_HINT='' PREFLIGHT_FIX_DESC='' PREFLIGHT_FIX_FN=''
  git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 || return 0
  local ahead
  ahead="$(git rev-list --count 'HEAD..@{u}')"
  ((ahead == 0)) && return 0
  PREFLIGHT_MSG="remote has $ahead new commit(s) ahead of local"
  PREFLIGHT_FIX_HINT="Try: --auto-fix to rebase onto the remote first."
  PREFLIGHT_FIX_DESC="git pull --rebase (aborts on conflict)"
  PREFLIGHT_FIX_FN=preflight_ch5_fix
  return 1
}

preflight_ch5_fix() {
  git pull --rebase
}
