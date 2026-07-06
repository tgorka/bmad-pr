# Shared bats helpers: stub binaries, throwaway git repos, script paths.
# Sourced by every .bats file via: load helpers/common

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export REPO_ROOT
export BMAD_PR_BIN="$REPO_ROOT/scripts/bmad-pr"
export LIB_DIR="$REPO_ROOT/scripts/lib"

# Create a stub directory and prepend it to PATH. Call once in setup().
stub_init() {
  STUB_DIR="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUB_DIR"
  PATH="$STUB_DIR:$PATH"
  export STUB_DIR PATH
}

# make_stub <name> reads the stub body from stdin. Every invocation of the stub
# appends its argv (one line, args joined with \x1f) to $STUB_DIR/<name>.calls
# before the body runs. The body may read recorded state or dispatch on "$1".
make_stub() {
  local name=$1
  {
    printf '#!/usr/bin/env bash\n'
    # Record argv with an unlikely separator so tests can assert exact args.
    printf 'printf "%%s\\n" "$(IFS=$'"'"'\\x1f'"'"'; echo "$*")" >> "%s/%s.calls"\n' \
      "$STUB_DIR" "$name"
    cat
  } >"$STUB_DIR/$name"
  chmod +x "$STUB_DIR/$name"
}

# Print recorded calls for a stub (empty if never called).
stub_calls() { cat "$STUB_DIR/$1.calls" 2>/dev/null || true; }

stub_call_count() { stub_calls "$1" | wc -l | tr -d ' '; }

# Create a throwaway git repo with one commit on main; prints its path.
make_repo() {
  local dir="$BATS_TEST_TMPDIR/repo${1:+-$1}"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Test User"
  git -C "$dir" commit -q --allow-empty -m "init"
  echo "$dir"
}

# Add a bare "origin" remote to a repo and push main; prints the bare path.
add_origin() {
  local repo=$1 bare="$BATS_TEST_TMPDIR/origin${2:+-$2}.git"
  git init -q --bare -b main "$bare"
  git -C "$repo" remote add origin "$bare"
  git -C "$repo" push -q -u origin main
  echo "$bare"
}
