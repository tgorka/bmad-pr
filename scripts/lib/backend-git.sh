# shellcheck shell=bash
# Bare-git fallback: push the branch and print manual-PR instructions.
# Used when neither gt nor an authenticated gh is available, or the remote
# is not GitHub. The ledger still records the branch so stacking keeps
# working; PR number/url stay null.

# git_ship <branch> <parent> <title> <body_file> <draft> <amend_number>
# Prints "\t" (no PR number/url).
git_ship() {
  local branch=$1 parent=$2
  git push -u origin "$branch" >&2 || die "git push failed for $branch"

  local url
  url="$(git remote get-url origin)"
  # Normalize git@host:owner/repo(.git) and https://host/owner/repo(.git).
  url="${url%.git}"
  url="${url/#git@/https:\/\/}"
  # Only the ssh form has host:owner — convert the first ':' after the host.
  if [[ "$url" == https://*:* && "$url" != https://*/* ]]; then
    url="${url/:/\/}"
  fi
  log "no PR backend available — branch pushed; open the PR manually:"
  log "  $url/compare/$parent...$branch?expand=1"
  printf '\t\n'
}

git_retarget() {
  refuse "retarget needs gh or gt; bare git backend cannot edit PR bases"
}
