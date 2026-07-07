#!/usr/bin/env bats
# Retarget (parent PR merged) and reviewer_wait edge cases.

load helpers/common
load helpers/gh-stub

setup() {
  stub_init
  install_gh_stub
  REPO="$(make_repo)"
  add_origin "$REPO" >/dev/null
  cd "$REPO"
  export BMAD_PR_TOOL=gh BMAD_PR_REVIEWER=cubic BMAD_PR_POLL_INTERVAL=1
}

make_stack() {
  # parent 3.1 with one commit, child 3.2 stacked on it, both pushed
  git switch -qc bmad/story/3.1
  echo A >f.txt && git add f.txt && git commit -qm "parent work"
  git push -qu origin bmad/story/3.1
  PARENT_SHA="$(git rev-parse HEAD)"
  git switch -qc bmad/story/3.2
  echo C >c.txt && git add c.txt && git commit -qm "child work"
  git push -qu origin bmad/story/3.2
  CHILD_SHA="$(git rev-parse HEAD)"
  # simulate squash-merge of the parent into main
  git switch -q main
  git merge -q --squash bmad/story/3.1 >/dev/null
  git commit -qm "squash-merge 3.1"
  git push -q origin main
  git switch -q bmad/story/3.2

  mkdir -p "$REPO/_bmad-output/pr"
  jq -n --arg psha "$PARENT_SHA" '
    {schema: 1, story: "3.2", branch: "bmad/story/3.2",
     parentBranch: "bmad/story/3.1", parentSha: $psha, parentPr: 41,
     pr: {number: 42, url: "https://github.com/o/r/pull/42", state: "open"},
     phase: "dev-story", runId: "run-1", tool: "gh",
     reviewer: {provider: "cubic", lastReviewedSha: null, lastScore: null, approved: false},
     openedAt: "2026-07-01T10:00:00Z", lastAmendedAt: "2026-07-01T10:00:00Z"}' \
    >"$REPO/_bmad-output/pr/3.2.json"
}

@test "retarget rebases onto new base, pushes, retargets PR, updates ledger" {
  make_stack
  run "$BMAD_PR_BIN" retarget --story 3.2
  [ "$status" -eq 0 ]
  gh_called "pr view 41"
  gh_called "pr edit 42 --base main"
  # branch now sits on origin/main
  [ "$(git merge-base HEAD origin/main)" = "$(git rev-parse origin/main)" ]
  # and was force-pushed
  [ "$(git rev-parse origin/bmad/story/3.2)" = "$(git rev-parse HEAD)" ]
  entry="$REPO/_bmad-output/pr/3.2.json"
  [ "$(jq -r '.parentPr' "$entry")" = "null" ]
  [ "$(jq -r '.parentBranch' "$entry")" = "null" ]
}

@test "retarget conflict refuses, aborts rebase, does NOT retarget the PR" {
  make_stack
  # make main conflict with the child's commit (add/add on c.txt)
  git switch -q main
  echo M >c.txt && git add c.txt && git commit -qm "conflicting main work"
  git push -q origin main
  git switch -q bmad/story/3.2

  run "$BMAD_PR_BIN" retarget --story 3.2
  [ "$status" -eq 2 ]
  [[ "$output" == *"hit conflicts"* ]]
  gh_not_called "pr edit"
  # rebase was aborted, branch untouched
  [ ! -d "$(git rev-parse --git-dir)/rebase-merge" ]
  [ ! -d "$(git rev-parse --git-dir)/rebase-apply" ]
  [ "$(git rev-parse HEAD)" = "$CHILD_SHA" ]
}

@test "retarget --dry-run plans and mutates nothing" {
  make_stack
  run "$BMAD_PR_BIN" retarget --story 3.2 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan: rebase bmad/story/3.2"* ]]
  gh_not_called "pr edit"
  # branch untouched locally and on the remote
  [ "$(git rev-parse HEAD)" = "$CHILD_SHA" ]
  [ "$(git rev-parse origin/bmad/story/3.2)" = "$CHILD_SHA" ]
  [ "$(jq -r '.parentPr' "$REPO/_bmad-output/pr/3.2.json")" = "41" ]
}

@test "retarget refuses when parent PR is not merged" {
  make_stack
  export GH_STUB_PR_STATE_JSON='{"state":"OPEN","baseRefName":"main"}'
  run "$BMAD_PR_BIN" retarget --story 3.2
  [ "$status" -eq 2 ]
  [[ "$output" == *"not merged"* ]]
}

run_reviewer_wait() { # timeout since
  run bash -c "
    cd '$REPO'
    export PATH='$STUB_DIR:$PATH' LIB_SOURCE_DIR='$LIB_DIR'
    export BMAD_PR_REVIEWER_BOT_REGEX='^coderabbitai'
    export BMAD_PR_REVIEWER_COMPLETION=bot-review
    export BMAD_PR_POLL_INTERVAL=1
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/reviewer.sh'
    reviewer_wait 42 deadbeef '$1' '$2'"
}

@test "reviewer_latest_score truncates decimal captures from generic regexes" {
  export GH_STUB_REVIEWS='[{"user":{"login":"coderabbitai[bot]","type":"Bot"},"state":"COMMENTED","submitted_at":"2026-07-06T12:00:00Z","body":"score: 7.5"}]'
  run bash -c "
    cd '$REPO'
    export PATH='$STUB_DIR:$PATH' LIB_SOURCE_DIR='$LIB_DIR'
    export BMAD_PR_REVIEWER_BOT_REGEX='^coderabbitai'
    export BMAD_PR_SCORE_REGEX='score: ([0-9.]+)'
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/reviewer.sh'
    reviewer_latest_score 42"
  [ "$status" -eq 0 ]
  [ "$output" = "7" ]
}

@test "reviewer_wait bot-review: fresh review of the head completes" {
  export GH_STUB_REVIEWS='[{"user":{"login":"coderabbitai[bot]","type":"Bot"},"state":"COMMENTED","submitted_at":"2026-07-06T12:00:00Z","commit_id":"deadbeef","body":"done"}]'
  run_reviewer_wait 5 "2026-07-06T11:00:00Z"
  [ "$status" -eq 0 ]
  [ "$output" = "completed" ]
}

@test "reviewer_wait bot-review: stale reviews don't complete; full timeout, not absent" {
  export GH_STUB_REVIEWS='[{"user":{"login":"coderabbitai[bot]","type":"Bot"},"state":"COMMENTED","submitted_at":"2026-07-06T10:00:00Z","commit_id":"deadbeef","body":"old"}]'
  run_reviewer_wait 3 "2026-07-06T11:00:00Z"
  [ "$status" -eq 1 ]
  [ "$output" = "timeout" ]
}

@test "reviewer_wait bot-review: late review of a DIFFERENT commit doesn't complete" {
  export GH_STUB_REVIEWS='[{"user":{"login":"coderabbitai[bot]","type":"Bot"},"state":"COMMENTED","submitted_at":"2026-07-06T12:00:00Z","commit_id":"0ldc0mmit","body":"late but stale"}]'
  run_reviewer_wait 3 "2026-07-06T11:00:00Z"
  [ "$status" -eq 1 ]
  [ "$output" = "timeout" ]
}

@test "reviewer_check_state: freshly queued run wins over older completed run" {
  export GH_STUB_CHECKRUNS='{"check_runs":[
    {"name":"cubic","status":"completed","started_at":"2026-07-06T11:00:00Z","completed_at":"2026-07-06T12:00:00Z"},
    {"name":"cubic","status":"queued"}]}'
  run bash -c "
    cd '$REPO'
    export PATH='$STUB_DIR:$PATH' LIB_SOURCE_DIR='$LIB_DIR'
    export BMAD_PR_REVIEWER_CHECK_REGEX='^cubic'
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/reviewer.sh'
    reviewer_check_state deadbeef"
  [ "$status" -eq 0 ]
  [ "$output" = "queued" ]
}

@test "reviewer_approved reflects the LATEST review state, not any past approval" {
  export GH_STUB_REVIEWS='[
    {"user":{"login":"cubic-dev-ai[bot]","type":"Bot"},"state":"APPROVED","submitted_at":"2026-07-06T10:00:00Z","commit_id":"deadbeef","body":"lgtm"},
    {"user":{"login":"cubic-dev-ai[bot]","type":"Bot"},"state":"COMMENTED","submitted_at":"2026-07-06T11:00:00Z","commit_id":"deadbeef","body":"actually, issues found"}]'
  run bash -c "
    cd '$REPO'
    export PATH='$STUB_DIR:$PATH' LIB_SOURCE_DIR='$LIB_DIR'
    export BMAD_PR_REVIEWER_BOT_REGEX='^cubic'
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/reviewer.sh'
    reviewer_approved 42 deadbeef"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
