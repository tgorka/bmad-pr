# shellcheck shell=bash
# gt (Graphite) backend: native stacking. gt owns branch metadata, bases and
# pushes — never pass a base to submit manually. Verified against gt 1.8.6.

# gt_ship <branch> <parent> <title> <body_file> <draft> <amend_number>
# Prints "<number>\t<url>" when gh is available for querying, else "\t".
gt_ship() {
  local branch=$1 parent=$2 title=$3 body_file=$4 draft=$5 amend_number=$6

  # Branches created outside gt are untracked and fail gt operations; track
  # with the stack parent. On an already-tracked branch this is a no-op/error
  # we tolerate — gt refuses to corrupt existing stack metadata.
  gt track --parent "$parent" >&2 2>/dev/null || true

  # Submits this branch and its ancestors; new PRs default to draft under
  # --no-interactive, and bases come from the tracked stack.
  local -a args=(submit --no-interactive --no-edit)
  [[ "$draft" == true ]] && args+=(--draft)
  gt "${args[@]}" >&2 || die "gt submit failed (try: gt restack, then re-run)"

  local number="" url=""
  if backend_query_available; then
    number="$(gh_pr_open_number "$branch")"
    if [[ -n "$number" ]]; then
      url="$(gh pr view "$number" --json url --jq .url)"
      if [[ -n "$body_file" ]]; then
        gh pr edit "$number" --body-file "$body_file" >/dev/null || true
        [[ -n "$title" && -z "$amend_number" ]] &&
          gh pr edit "$number" --title "$title" >/dev/null || true
      fi
    fi
  else
    warn "gh unavailable — PR submitted via gt, but number/url not recorded"
  fi
  printf '%s\t%s\n' "$number" "$url"
}

# Parent merged: gt sync deletes merged branches and reparents children; the
# follow-up submit updates PR bases on GitHub.
gt_retarget() {
  gt sync -f --delete-all --no-interactive >&2 ||
    refuse "gt sync failed — resolve conflicts (gt add . && gt continue), then re-run"
  gt submit --no-interactive --no-edit >&2 ||
    die "gt submit failed after sync"
}
