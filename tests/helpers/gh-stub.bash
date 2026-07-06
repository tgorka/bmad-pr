# A configurable gh stub. Behavior is driven by GH_STUB_* env vars so each
# test declares exactly the GitHub state it needs. All argv are recorded by
# make_stub into $STUB_DIR/gh.calls (fields joined with \x1f).

install_gh_stub() {
  make_stub gh <<'EOF'
all="$*"
case "$all" in
  auth\ status*) exit 0 ;;
  repo\ view*) printf 'o/r\n' ;;
  pr\ checks*) printf '%s\n' "${GH_STUB_CHECKS:-[]}" ;;
  *check-runs*)
    if [ -n "${GH_STUB_CHECKRUNS:-}" ]; then
      printf '%s\n' "$GH_STUB_CHECKRUNS"
    else
      printf '{"check_runs":[]}\n'
    fi
    ;;
  *graphql*)
    if [ -n "${GH_STUB_GRAPHQL:-}" ]; then
      printf '%s\n' "$GH_STUB_GRAPHQL"
    else
      printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}\n'
    fi
    ;;
  *reviews*) printf '%s\n' "${GH_STUB_REVIEWS:-[]}" ;;
  *headRefOid*) printf '%s\n' "${GH_STUB_HEAD_SHA:-deadbeef}" ;;
  *state,baseRefName*)
    if [ -n "${GH_STUB_PR_STATE_JSON:-}" ]; then
      printf '%s\n' "$GH_STUB_PR_STATE_JSON"
    else
      printf '{"state":"MERGED","baseRefName":"main"}\n'
    fi
    ;;
  pr\ list*) printf '%s\n' "${GH_STUB_OPEN_PR:-}" ;;
  pr\ create*) printf 'https://github.com/o/r/pull/%s\n' "${GH_STUB_NEW_PR:-42}" ;;
  pr\ view*) printf 'https://github.com/o/r/pull/42\n' ;;
  pr\ edit*) exit 0 ;;
  pr\ comment*) exit 0 ;;
  *) exit 0 ;;
esac
EOF
}

# Assert a gh call matching all given substrings happened (order-insensitive
# within one call line; \x1f separators normalized to spaces). -F: needles
# are literal substrings, not regexes.
gh_called() {
  local line
  line="$(stub_calls gh | tr '\034\037' '  ')"
  local needle
  for needle in "$@"; do
    grep -qF -- "$needle" <<<"$line" || return 1
  done
}

gh_not_called() {
  ! stub_calls gh | tr '\037' ' ' | grep -qF -- "$1"
}
