#!/usr/bin/env bats

load helpers/common

setup() {
  stub_init
  export LIB_SOURCE_DIR="$LIB_DIR"
  source "$LIB_DIR/common.sh"
  source "$LIB_DIR/backend.sh"
  REPO="$(make_repo)"
  cd "$REPO"
}

@test "explicit BMAD_PR_TOOL override wins" {
  BMAD_PR_TOOL=git run backend_detect
  [ "$output" = "git" ]
  BMAD_PR_TOOL=gt run backend_detect
  [ "$output" = "gt" ]
}

@test "invalid BMAD_PR_TOOL refuses" {
  export BMAD_PR_TOOL=hub
  run backend_detect
  [ "$status" -eq 2 ]
}

@test "no origin remote → git" {
  export BMAD_PR_TOOL=auto
  run backend_detect
  [ "$output" = "git" ]
}

@test "non-GitHub remote → git even with gh available" {
  git remote add origin https://gitlab.com/o/r.git
  make_stub gh <<'EOF'
exit 0
EOF
  export BMAD_PR_TOOL=auto
  run backend_detect
  [ "$output" = "git" ]
}

@test "GitHub remote + authenticated gh → gh" {
  git remote add origin https://github.com/o/r.git
  make_stub gh <<'EOF'
exit 0
EOF
  export BMAD_PR_TOOL=auto
  run backend_detect
  [ "$output" = "gh" ]
}

@test "GitHub remote + unauthenticated gh → git" {
  git remote add origin https://github.com/o/r.git
  make_stub gh <<'EOF'
exit 1
EOF
  export BMAD_PR_TOOL=auto
  run backend_detect
  [ "$output" = "git" ]
}

@test "gt config in git common dir wins over gh" {
  git remote add origin git@github.com:o/r.git
  make_stub gh <<'EOF'
exit 0
EOF
  make_stub gt <<'EOF'
exit 0
EOF
  echo '{"trunk":"main"}' >"$(git rev-parse --git-common-dir)/.graphite_repo_config"
  export BMAD_PR_TOOL=auto
  run backend_detect
  [ "$output" = "gt" ]
}

@test "gt binary without repo init falls through to gh" {
  git remote add origin git@github.com:o/r.git
  make_stub gh <<'EOF'
exit 0
EOF
  make_stub gt <<'EOF'
exit 0
EOF
  export BMAD_PR_TOOL=auto
  run backend_detect
  [ "$output" = "gh" ]
}
