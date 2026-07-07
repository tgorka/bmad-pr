#!/usr/bin/env bats
# DW-1..DW-9 backlog features (spec-dw-backlog-1.md).

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

# ── DW-1: titles, template, labels ───────────────────────────────────────────

@test "build_title: conventional format and emoji prefix" {
  run bash -c "source '$BMAD_PR_BIN'
    BMAD_PR_TITLE_FORMAT=conventional build_title 3.2 dev-story"
  [ "$output" = "feat(story-3.2): dev-story" ]
  run bash -c "source '$BMAD_PR_BIN'
    BMAD_PR_TITLE_FORMAT=bmad BMAD_PR_TITLE_EMOJI=true build_title 3.2 dev-story"
  [ "$output" = "💻 BMAD: 3.2 dev-story" ]
  run bash -c "source '$BMAD_PR_BIN'
    BMAD_PR_TITLE_EMOJI=true build_title 3.2 prd"
  [ "$output" = "📋 BMAD: 3.2 prd" ]
}

@test "ship refuses an invalid BMAD_PR_TITLE_FORMAT" {
  export BMAD_PR_TITLE_FORMAT=haiku
  run "$BMAD_PR_BIN" ship --story 3.2 --phase dev-story --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"BMAD_PR_TITLE_FORMAT"* ]]
}

@test "body template renders placeholders literally, unknown ones pass through" {
  mkdir -p "$REPO/.github"
  cat >"$REPO/.github/bmad-pr-template.md" <<'EOF'
Story {{story}} / {{phase}} — parent #{{parent_pr}} run {{run_id}} keep {{unknown}} $(no-eval)
EOF
  run bash -c "cd '$REPO'; source '$BMAD_PR_BIN'
    ROOT='$REPO'
    export BMAD_PR_LEDGER_DIR=_bmad-output/pr
    f=\$(build_body_file 3.2 dev-story 41 run-9); cat \"\$f\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Story 3.2 / dev-story — parent #41 run run-9 keep {{unknown}} \$(no-eval)"* ]]
}

@test "body template: {{parent_pr}} renders 'none' without a stack parent" {
  mkdir -p "$REPO/.github"
  printf 'p=#{{parent_pr}}\n' >"$REPO/.github/bmad-pr-template.md"
  run bash -c "cd '$REPO'; source '$BMAD_PR_BIN'
    ROOT='$REPO'
    export BMAD_PR_LEDGER_DIR=_bmad-output/pr
    f=\$(build_body_file 3.2 dev-story '' run-9); cat \"\$f\""
  [[ "$output" == *"p=#none"* ]]
}

@test "ship applies BMAD_PR_LABELS on creation (edges trimmed, spaces kept)" {
  export BMAD_PR_LABELS="bmad, story work ,"
  run "$BMAD_PR_BIN" ship --story 3.2 --phase dev-story
  [ "$status" -eq 0 ]
  gh_called "--label bmad" "--label story work"
}

# ── DW-2: planning stacks ────────────────────────────────────────────────────

@test "ship --planning defaults the key and uses a planning branch" {
  run "$BMAD_PR_BIN" ship --planning --phase prd
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "bmad/planning/prd" ]
  [ -f "$REPO/_bmad-output/pr/planning-prd.json" ]
  gh_called "--head bmad/planning/prd"
}

@test "planning phases stack on the previous planning PR" {
  run "$BMAD_PR_BIN" ship --planning --phase prd
  [ "$status" -eq 0 ]
  git switch -q main
  export GH_STUB_NEW_PR=43
  run "$BMAD_PR_BIN" ship --planning --phase architecture
  [ "$status" -eq 0 ]
  gh_called "--base bmad/planning/prd"
  [ "$(jq -r '.parentBranch' "$REPO/_bmad-output/pr/planning-architecture.json")" = "bmad/planning/prd" ]
}

# ── DW-3: remotes and forks ──────────────────────────────────────────────────

@test "remote_slug parses https, ssh and scp-style URLs" {
  source "$LIB_DIR/common.sh"
  git remote add r1 https://github.com/owner/repo.git
  git remote add r2 git@github.com:owner/repo.git
  git remote add r3 ssh://git@github.com/owner/repo.git
  [ "$(remote_slug r1)" = "owner/repo" ]
  [ "$(remote_slug r2)" = "owner/repo" ]
  [ "$(remote_slug r3)" = "owner/repo" ]
  run remote_slug origin # local path remote → unparseable
  [ "$status" -eq 1 ]
  run remote_slug nonexistent
  [ "$status" -eq 1 ]
}

@test "BMAD_PR_REMOTE pushes the story branch to the configured remote" {
  local alt="$BATS_TEST_TMPDIR/alt.git"
  git init -q --bare -b main "$alt"
  git remote add alt "$alt"
  git push -qu alt main
  export BMAD_PR_REMOTE=alt
  run "$BMAD_PR_BIN" ship --story 3.2 --phase dev-story
  [ "$status" -eq 0 ]
  git ls-remote --exit-code --heads alt bmad/story/3.2 >/dev/null
  ! git ls-remote --exit-code --heads origin bmad/story/3.2 >/dev/null 2>&1
}

@test "fork flow: gh_ship targets upstream with a fork-qualified head" {
  make_stub git <<'EOF'
case "$*" in
  "remote get-url upstream") echo "https://github.com/up/base.git" ;;
  "remote get-url origin") echo "git@github.com:me/base.git" ;;
  push*) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  run bash -c "
    export PATH='$STUB_DIR:$PATH' LIB_SOURCE_DIR='$LIB_DIR'
    export BMAD_PR_REMOTE=origin
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/reviewer.sh'
    source '$LIB_DIR/backend-gh.sh'
    body=\$(mktemp)
    gh_ship bmad/story/9.9 main 'BMAD: 9.9 dev-story' \"\$body\" true ''"
  [ "$status" -eq 0 ]
  gh_called "--repo up/base" "--head me:bmad/story/9.9"
}

@test "fork flow: gh_retarget rebases from upstream, pushes to the fork" {
  make_stub git <<'EOF'
case "$*" in
  "remote get-url upstream") echo "https://github.com/up/base.git" ;;
  *) exit 0 ;;
esac
EOF
  run bash -c "
    export PATH='$STUB_DIR:$PATH' LIB_SOURCE_DIR='$LIB_DIR'
    export BMAD_PR_REMOTE=origin
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/reviewer.sh'
    source '$LIB_DIR/backend-gh.sh'
    gh_retarget 42 main bmad/story/3.2 abc123"
  [ "$status" -eq 0 ]
  stub_calls git | tr '\037' ' ' | grep -q '^fetch upstream$'
  stub_calls git | tr '\037' ' ' | grep -q '^rebase --onto upstream/main abc123 bmad/story/3.2$'
  stub_calls git | tr '\037' ' ' | grep -q '^push --force-with-lease origin bmad/story/3.2$'
  gh_called "pr edit 42" "--repo up/base" "--base main"
}

@test "fork flow: PR adoption queries the base repo with owner-qualified head" {
  make_stub git <<'EOF'
case "$*" in
  "remote get-url upstream") echo "https://github.com/up/base.git" ;;
  "remote get-url origin") echo "git@github.com:me/base.git" ;;
  *) exit 0 ;;
esac
EOF
  export GH_STUB_OPEN_PR=88
  run bash -c "
    export PATH='$STUB_DIR:$PATH' LIB_SOURCE_DIR='$LIB_DIR'
    export BMAD_PR_REMOTE=origin
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/reviewer.sh'
    source '$LIB_DIR/backend-gh.sh'
    gh_pr_open_number bmad/story/9.9"
  [ "$status" -eq 0 ]
  [ "$output" = "88" ]
  gh_called "repos/up/base/pulls?head=me:bmad/story/9.9"
}

@test "fork flow: amend edits the PR in the base repo" {
  make_stub git <<'EOF'
case "$*" in
  "remote get-url upstream") echo "https://github.com/up/base.git" ;;
  "remote get-url origin") echo "git@github.com:me/base.git" ;;
  *) exit 0 ;;
esac
EOF
  run bash -c "
    export PATH='$STUB_DIR:$PATH' LIB_SOURCE_DIR='$LIB_DIR'
    export BMAD_PR_REMOTE=origin
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/reviewer.sh'
    source '$LIB_DIR/backend-gh.sh'
    body=\$(mktemp)
    gh_ship bmad/story/9.9 main 'BMAD: 9.9 dev-story' \"\$body\" true 42"
  [ "$status" -eq 0 ]
  gh_called "pr edit 42" "--repo up/base"
}

# ── DW-4: gt-aware CH2 hint ──────────────────────────────────────────────────

@test "CH2 in a gt repo hints gt continue" {
  echo '{"trunk":"main"}' >"$(git rev-parse --git-common-dir)/.graphite_repo_config"
  mkdir -p "$(git rev-parse --git-dir)/rebase-merge"
  run "$BMAD_PR_BIN" preflight
  [ "$status" -eq 2 ]
  [[ "$output" == *"gt restack"* ]]
  [[ "$output" == *"gt continue"* ]]
}

# ── DW-6: ledger lock ────────────────────────────────────────────────────────

@test "ledger_update refuses when the entry lock is held" {
  mkdir -p "$REPO/_bmad-output/pr"
  jq -n '{schema:1, story:"3.2", branch:"b", pr:{state:"open"}, openedAt:"t", lastAmendedAt:"t"}' \
    >"$REPO/_bmad-output/pr/3.2.json"
  mkdir "$REPO/_bmad-output/pr/3.2.json.lock"
  run bash -c "
    cd '$REPO'
    export LIB_SOURCE_DIR='$LIB_DIR' BMAD_PR_LEDGER_DIR=_bmad-output/pr
    export BMAD_PR_LOCK_TIMEOUT=1
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/ledger.sh'
    ledger_update 3.2 '.phase = \"x\"'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ledger busy"* ]]
}

@test "ledger_update releases its lock after success" {
  mkdir -p "$REPO/_bmad-output/pr"
  jq -n '{schema:1, story:"3.2", branch:"b", pr:{state:"open"}, openedAt:"t", lastAmendedAt:"t"}' \
    >"$REPO/_bmad-output/pr/3.2.json"
  run bash -c "
    cd '$REPO'
    export LIB_SOURCE_DIR='$LIB_DIR' BMAD_PR_LEDGER_DIR=_bmad-output/pr
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/ledger.sh'
    ledger_update 3.2 '.phase = \"x\"'"
  [ "$status" -eq 0 ]
  [ ! -d "$REPO/_bmad-output/pr/3.2.json.lock" ]
  [ "$(jq -r '.phase' "$REPO/_bmad-output/pr/3.2.json")" = "x" ]
}

# ── DW-8: CH3 stage mode ─────────────────────────────────────────────────────

@test "BMAD_PR_STAGE_MODE=tracked stages only tracked modifications" {
  mkdir -p _bmad-output
  echo base >_bmad-output/tracked.md
  git add _bmad-output/tracked.md && git commit -qm "seed artifact"
  echo more >>_bmad-output/tracked.md
  echo new >_bmad-output/new.md
  echo stray >stray.txt
  export BMAD_PR_STAGE_MODE=tracked
  run "$BMAD_PR_BIN" preflight --auto-fix
  [ "$status" -eq 2 ] # stray residue still refuses
  git diff --cached --name-only | grep -q '_bmad-output/tracked.md'
  ! git diff --cached --name-only | grep -q '_bmad-output/new.md'
}

# ── DW-9: CH1 branch suffix carries the PID ──────────────────────────────────

@test "CH1 auto-fix branch name includes epoch and pid" {
  git checkout -q --detach HEAD
  run "$BMAD_PR_BIN" preflight --auto-fix
  [ "$status" -eq 0 ]
  [[ "$(git rev-parse --abbrev-ref HEAD)" =~ ^bmad-pr/[0-9a-f]+-[0-9]+-[0-9]+$ ]]
}
