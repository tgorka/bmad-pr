#!/usr/bin/env bats

load helpers/common
load helpers/gh-stub

setup() {
  stub_init
  install_gh_stub
  REPO="$(make_repo)"
  add_origin "$REPO" >/dev/null
  cd "$REPO"
  export BMAD_PR_TOOL=gh BMAD_PR_REVIEWER=cubic
}

write_ledger() { # key branch parent_branch parent_pr number state openedAt
  mkdir -p "$REPO/_bmad-output/pr"
  jq -n --arg story "$1" --arg branch "$2" --arg pb "$3" --arg ppr "$4" \
    --arg n "$5" --arg state "$6" --arg t "$7" '
    {schema: 1, story: $story, branch: $branch,
     parentBranch: (if $pb == "" then null else $pb end),
     parentSha: null,
     parentPr: (if $ppr == "" then null else ($ppr | tonumber) end),
     pr: {number: ($n | tonumber), url: ("https://github.com/o/r/pull/" + $n), state: $state},
     phase: "dev-story", runId: "run-1", tool: "gh",
     reviewer: {provider: "cubic", lastReviewedSha: null, lastScore: null, approved: false},
     openedAt: $t, lastAmendedAt: $t}' >"$REPO/_bmad-output/pr/$1.json"
}

@test "ship --dry-run on trunk prints plan, mutates nothing" {
  run "$BMAD_PR_BIN" ship --story 3.2 --phase dev-story --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan: tool=gh"* ]]
  [[ "$output" == *"plan: branch=bmad/story/3.2 (create from main)"* ]]
  [[ "$output" == *"plan: base=main"* ]]
  [[ "$output" == *'plan: action=create draft PR titled "BMAD: 3.2 dev-story"'* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
  [ ! -e "$REPO/_bmad-output/pr/3.2.json" ]
  gh_not_called "pr create"
}

@test "ship creates story branch, draft PR, and ledger entry" {
  run "$BMAD_PR_BIN" ship --story 3.2 --phase dev-story --run-id run-7
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://github.com/o/r/pull/42"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "bmad/story/3.2" ]
  gh_called "pr create" "--base main" "--head bmad/story/3.2" "--draft" "--title BMAD: 3.2 dev-story"
  local entry="$REPO/_bmad-output/pr/3.2.json"
  [ -f "$entry" ]
  [ "$(jq -r '.pr.number' "$entry")" = "42" ]
  [ "$(jq -r '.runId' "$entry")" = "run-7" ]
  [ "$(jq -r '.pr.state' "$entry")" = "open" ]
  # branch was pushed to origin
  git ls-remote --exit-code --heads origin bmad/story/3.2 >/dev/null
}

@test "ship stacks on the previous story's open PR" {
  git switch -qc bmad/story/3.1
  git commit -q --allow-empty -m "story 3.1"
  git push -qu origin bmad/story/3.1
  git switch -q main
  write_ledger 3.1 bmad/story/3.1 "" "" 41 open 2026-07-01T10:00:00Z

  run "$BMAD_PR_BIN" ship --story 3.2 --phase dev-story
  [ "$status" -eq 0 ]
  gh_called "pr create" "--base bmad/story/3.1"
  local entry="$REPO/_bmad-output/pr/3.2.json"
  [ "$(jq -r '.parentBranch' "$entry")" = "bmad/story/3.1" ]
  [ "$(jq -r '.parentPr' "$entry")" = "41" ]
  [ "$(jq -r '.parentSha' "$entry")" = "$(git rev-parse bmad/story/3.1)" ]
  # story branch starts at the parent tip
  [ "$(git merge-base HEAD bmad/story/3.1)" = "$(git rev-parse bmad/story/3.1)" ]
}

@test "ship --base overrides stack resolution" {
  git switch -qc custom-base
  git push -qu origin custom-base
  git switch -q main
  run "$BMAD_PR_BIN" ship --story 3.2 --phase dev-story --base custom-base
  [ "$status" -eq 0 ]
  gh_called "pr create" "--base custom-base"
}

@test "ship amends when ledger has an open PR" {
  git switch -qc bmad/story/3.2
  git push -qu origin bmad/story/3.2
  write_ledger 3.2 bmad/story/3.2 "" "" 42 open 2026-07-01T10:00:00Z

  run "$BMAD_PR_BIN" ship --story 3.2 --phase code-review
  [ "$status" -eq 0 ]
  gh_called "pr edit 42 --body-file"
  gh_not_called "pr create"
  local entry="$REPO/_bmad-output/pr/3.2.json"
  [ "$(jq -r '.phase' "$entry")" = "code-review" ]
  [ "$(jq -r '.runId' "$entry")" = "run-1" ] # preserved on amend
  [ "$(jq -r '.lastAmendedAt' "$entry")" != "2026-07-01T10:00:00Z" ]
}

@test "ship adopts an existing open PR the ledger missed" {
  git switch -qc bmad/story/3.2
  git push -qu origin bmad/story/3.2
  export GH_STUB_OPEN_PR=77
  run "$BMAD_PR_BIN" ship --story 3.2 --phase dev-story
  [ "$status" -eq 0 ]
  gh_called "pr edit 77"
  gh_not_called "pr create"
  [ "$(jq -r '.pr.number' "$REPO/_bmad-output/pr/3.2.json")" = "77" ]
}

@test "ship refuses on unrelated branch" {
  git switch -qc feature/other
  run "$BMAD_PR_BIN" ship --story 3.2 --phase dev-story
  [ "$status" -eq 2 ]
  [[ "$output" == *"unrelated branch"* ]]
}

@test "ship refuses when ledger entry is merged" {
  git switch -qc bmad/story/3.2
  write_ledger 3.2 bmad/story/3.2 "" "" 42 merged 2026-07-01T10:00:00Z
  run "$BMAD_PR_BIN" ship --story 3.2 --phase dev-story
  [ "$status" -eq 2 ]
  [[ "$output" == *"already has a merged PR"* ]]
}

@test "ship --amend refuses without a ledger entry" {
  run "$BMAD_PR_BIN" ship --story 9.9 --phase dev-story --amend
  [ "$status" -eq 2 ]
  [[ "$output" == *"--amend"* ]]
}

@test "ship refuses when ledger branch mismatches current branch" {
  git switch -qc bmad/story/3.9
  write_ledger 3.2 bmad/story/3.2 "" "" 42 open 2026-07-01T10:00:00Z
  run "$BMAD_PR_BIN" ship --story 3.2 --phase dev-story
  [ "$status" -eq 2 ]
  [[ "$output" == *"belongs to branch bmad/story/3.2"* ]]
}

@test "ship without required flags refuses" {
  run "$BMAD_PR_BIN" ship --phase dev-story
  [ "$status" -eq 2 ]
  run "$BMAD_PR_BIN" ship --story 3.2
  [ "$status" -eq 2 ]
}

@test "git backend pushes and prints manual instructions" {
  export BMAD_PR_TOOL=git
  run "$BMAD_PR_BIN" ship --story 3.2 --phase dev-story
  [ "$status" -eq 0 ]
  [[ "$output" == *"open the PR manually"* ]]
  git ls-remote --exit-code --heads origin bmad/story/3.2 >/dev/null
  [ "$(jq -r '.pr.number' "$REPO/_bmad-output/pr/3.2.json")" = "null" ]
  [ "$(jq -r '.branch' "$REPO/_bmad-output/pr/3.2.json")" = "bmad/story/3.2" ]
}
