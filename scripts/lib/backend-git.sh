# shellcheck shell=bash
# Bare-git fallback: push the branch and print manual-PR instructions.
# Used when neither gt nor an authenticated gh is available, or the remote
# is not GitHub. The ledger still records the branch so stacking keeps
# working; PR number/url stay null.

# Normalize a git remote URL to a browsable https base (best effort).
# Handles https://host/owner/repo(.git), git@host:owner/repo(.git) and
# ssh://git@host/owner/repo(.git).
git_compare_url() {
  local url=$1 rest
  url="${url%.git}"
  case "$url" in
    git@*:*)
      rest="${url#git@}"
      url="https://${rest/:/\/}"
      ;;
    ssh://git@*)
      url="https://${url#ssh://git@}"
      ;;
  esac
  printf '%s\n' "$url"
}

# git_ship <branch> <parent> <title> <body_file> <draft> <amend_number>
# Prints "\t" (no PR number/url).
git_ship() {
  local branch=$1 parent=$2
  git push -u origin "$branch" >&2 || die "git push failed for $branch"

  local url
  url="$(git_compare_url "$(git remote get-url origin)")"
  log "no PR backend available — branch pushed; open the PR manually:"
  log "  $url/compare/$parent...$branch?expand=1"
  printf '\t\n'
}

git_retarget() {
  refuse "retarget needs gh or gt; bare git backend cannot edit PR bases"
}
