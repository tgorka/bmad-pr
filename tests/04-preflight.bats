#!/usr/bin/env bats

load helpers/common

setup() {
  export LIB_SOURCE_DIR="$LIB_DIR"
  source "$LIB_DIR/common.sh"
  source "$LIB_DIR/preflight.sh"
  export BMAD_PR_STAGE_GLOB="_bmad-output/"
  REPO="$(make_repo)"
  cd "$REPO"
}

run_preflight() { # auto_fix dry_run
  run bash -c "
    cd '$REPO'
    export BMAD_PR_STAGE_GLOB='_bmad-output/'
    source '$LIB_DIR/common.sh'; source '$LIB_DIR/preflight.sh'
    preflight_run '${1:-false}' '${2:-false}'"
}

@test "clean repo passes preflight" {
  run_preflight false false
  [ "$status" -eq 0 ]
}

@test "CH1: detached HEAD refuses with hint" {
  git checkout -q --detach HEAD
  run_preflight false false
  [ "$status" -eq 2 ]
  [[ "$output" == *"detached HEAD"* ]]
  [[ "$output" == *"--auto-fix"* ]]
}

@test "CH1: auto-fix creates bmad-pr/<sha>-<ts> branch" {
  git checkout -q --detach HEAD
  run_preflight true false
  [ "$status" -eq 0 ]
  cd "$REPO"
  [[ "$(git rev-parse --abbrev-ref HEAD)" == bmad-pr/* ]]
}

@test "CH1: dry-run refuses instead of fixing" {
  git checkout -q --detach HEAD
  run_preflight true true
  [ "$status" -eq 2 ]
  [[ "$output" == *"dry-run"* ]]
  cd "$REPO"
  [ "$(git rev-parse --abbrev-ref HEAD)" = "HEAD" ]
}

@test "CH2: merge in progress refuses hard even with auto-fix" {
  git switch -qc feature
  echo a >file.txt && git add file.txt && git commit -qm a
  git switch -q main
  echo b >file.txt && git add file.txt && git commit -qm b
  run git merge feature
  [ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]
  run_preflight true false
  [ "$status" -eq 2 ]
  [[ "$output" == *"merge in progress"* ]]
}

@test "CH2: rebase in progress refuses hard" {
  mkdir -p "$(git rev-parse --git-dir)/rebase-merge"
  run_preflight true false
  [ "$status" -eq 2 ]
  [[ "$output" == *"rebase in progress"* ]]
}

@test "CH3: unstaged file outside scope refuses" {
  echo x >stray.txt
  run_preflight false false
  [ "$status" -eq 2 ]
  [[ "$output" == *"unstaged changes outside _bmad-output/"* ]]
  [[ "$output" == *"stray.txt"* ]]
}

@test "CH3: unstaged changes inside scope pass" {
  mkdir -p _bmad-output
  echo x >_bmad-output/notes.md
  run_preflight false false
  [ "$status" -eq 0 ]
}

@test "CH3: staged-only outside changes pass" {
  echo x >staged.txt
  git add staged.txt
  run_preflight false false
  [ "$status" -eq 0 ]
}

@test "CH3: auto-fix stages scope but refuses on outside residue" {
  mkdir -p _bmad-output
  echo x >_bmad-output/notes.md
  echo y >stray.txt
  run_preflight true false
  [ "$status" -eq 2 ]
  [[ "$output" == *"did not resolve"* ]]
  cd "$REPO"
  # scope path was staged by the bounded fix; stray remains untracked
  git diff --cached --name-only | grep -q '_bmad-output/notes.md'
  [ -z "$(git diff --cached --name-only | grep stray || true)" ]
}

@test "CH5: upstream ahead refuses with hint" {
  add_origin "$REPO" >/dev/null
  clone2="$BATS_TEST_TMPDIR/clone2"
  git clone -q "$(git remote get-url origin)" "$clone2"
  git -C "$clone2" config user.email t@e.c && git -C "$clone2" config user.name T
  git -C "$clone2" commit -q --allow-empty -m remote-work
  git -C "$clone2" push -q
  git fetch -q origin
  run_preflight false false
  [ "$status" -eq 2 ]
  [[ "$output" == *"new commit(s) ahead of local"* ]]
}

@test "CH5: auto-fix rebases onto upstream" {
  add_origin "$REPO" >/dev/null
  clone2="$BATS_TEST_TMPDIR/clone2"
  git clone -q "$(git remote get-url origin)" "$clone2"
  git -C "$clone2" config user.email t@e.c && git -C "$clone2" config user.name T
  git -C "$clone2" commit -q --allow-empty -m remote-work
  git -C "$clone2" push -q
  git fetch -q origin
  run_preflight true false
  [ "$status" -eq 0 ]
  cd "$REPO"
  [ "$(git rev-list --count 'HEAD..@{u}')" = "0" ]
}

@test "CH5: no upstream configured passes" {
  run_preflight false false
  [ "$status" -eq 0 ]
}
