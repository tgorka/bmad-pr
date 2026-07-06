# shellcheck shell=bash
# gh backend: stacked draft PRs with explicit --base/--head (research-verified
# against gh 2.95). Also the shared GitHub query surface (PR state, comments).

# Number of the open PR whose head is <branch>, or empty.
# (gh pr view alone would also resolve merged/closed PRs — don't use it here.)
gh_pr_open_number() {
  gh pr list --head "$1" --state open --json number --jq '.[0].number // empty'
}

# gh_ship <branch> <parent> <title> <body_file> <draft> <amend_number>
# Prints "<number>\t<url>".
gh_ship() {
  local branch=$1 parent=$2 title=$3 body_file=$4 draft=$5 amend_number=$6
  git push -u origin "$branch" >&2 || die "git push failed for $branch"

  if [[ -n "$amend_number" ]]; then
    # Title carries the phase — keep it in sync when amending.
    gh pr edit "$amend_number" --title "$title" --body-file "$body_file" >/dev/null ||
      die "gh pr edit $amend_number failed"
    local url
    url="$(gh pr view "$amend_number" --json url --jq .url)"
    printf '%s\t%s\n' "$amend_number" "$url"
    return 0
  fi

  local -a args=(pr create --base "$parent" --head "$branch"
    --title "$title" --body-file "$body_file")
  [[ "$draft" == true ]] && args+=(--draft)
  local url
  url="$(gh "${args[@]}" | tail -n1)"
  [[ "$url" == *"/pull/"* ]] || die "gh pr create returned no PR URL (got: $url)"
  # Pin the merge base so later bare `gh pr create` calls stack correctly.
  git config "branch.$branch.gh-merge-base" "$parent"
  printf '%s\t%s\n' "${url##*/}" "$url"
}

# gh_pr_state <number> → JSON {state, mergedAt, baseRefName, headRefOid, isDraft, url}
gh_pr_state() {
  gh pr view "$1" --json state,mergedAt,baseRefName,headRefOid,isDraft,url
}

gh_pr_comment() {
  gh pr comment "$1" --body "$2" >/dev/null
}

# gh_retarget <number> <new_base> <branch> <old_parent_sha>
# Parent merged: rebase our branch off the old parent tip onto the new base,
# push with lease, THEN retarget the PR base — a rebase conflict must not
# leave the PR pointing at a base its branch was never rebased onto. The
# only force-push in the tool.
gh_retarget() {
  local number=$1 new_base=$2 branch=$3 old_parent_sha=$4
  git fetch origin >&2
  git rebase --onto "origin/$new_base" "$old_parent_sha" "$branch" >&2 || {
    git rebase --abort >&2 || true
    refuse "rebase onto origin/$new_base hit conflicts; resolve manually (git rebase --onto origin/$new_base $old_parent_sha $branch), then re-run retarget"
  }
  git push --force-with-lease origin "$branch" >&2 ||
    die "git push --force-with-lease failed after retarget"
  gh pr edit "$number" --base "$new_base" >/dev/null ||
    die "gh pr edit --base $new_base failed (branch already rebased and pushed; re-run retarget)"
}
