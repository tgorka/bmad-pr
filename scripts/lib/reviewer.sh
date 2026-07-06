# shellcheck shell=bash
# Provider-agnostic reviewer engine. A provider profile (lib/reviewers/*.sh)
# supplies: BMAD_PR_REVIEWER_BOT_REGEX, BMAD_PR_REVIEWER_TRIGGER,
# BMAD_PR_REVIEWER_CHECK_REGEX (may be empty), BMAD_PR_REVIEWER_COMPLETION
# (check-run | bot-review), BMAD_PR_SCORE_REGEX (may be empty).
#
# All GitHub access goes through gh. gh api --jq cannot bind variables, so
# results are piped through real jq. REST/GraphQL pagination emits one JSON
# document per page — always merge with `jq -s`.

repo_slug() {
  if [[ -z "${_BMAD_PR_REPO_SLUG:-}" ]]; then
    _BMAD_PR_REPO_SLUG="$(gh repo view --json owner,name \
      --jq '"\(.owner.login)/\(.name)"')" || die "gh repo view failed"
  fi
  printf '%s\n' "$_BMAD_PR_REPO_SLUG"
}

# reviewer_check_state <sha> → queued|in_progress|completed|missing
reviewer_check_state() {
  local sha=$1
  if [[ -z "${BMAD_PR_REVIEWER_CHECK_REGEX:-}" ]]; then
    printf 'missing\n'
    return 0
  fi
  gh api "repos/$(repo_slug)/commits/$sha/check-runs" 2>/dev/null |
    jq -r --arg re "$BMAD_PR_REVIEWER_CHECK_REGEX" '
      [.check_runs[] | select(.name | test($re; "i"))]
      | last | .status // "missing"' || printf 'missing\n'
}

# All PR reviews (merged across pages) → JSON array.
reviewer_reviews() {
  local pr=$1
  gh api --paginate "repos/$(repo_slug)/pulls/$pr/reviews" 2>/dev/null |
    jq -s 'add // []' || printf '[]\n'
}

# reviewer_latest_score <pr> → the captured score number, or empty.
reviewer_latest_score() {
  local pr=$1
  [[ -n "${BMAD_PR_SCORE_REGEX:-}" ]] || return 0
  reviewer_reviews "$pr" |
    jq -r --arg bot "$BMAD_PR_REVIEWER_BOT_REGEX" --arg re "$BMAD_PR_SCORE_REGEX" '
      [ .[]
        | select(.user.type == "Bot")
        | select(.user.login | test($bot; "i"))
        | select(.body | test($re))
      ] | sort_by(.submitted_at) | last
      | if . == null then empty
        else (.body | match($re) | .captures[0].string)
        end'
}

# reviewer_approved <pr> → prints true|false
reviewer_approved() {
  local pr=$1
  reviewer_reviews "$pr" |
    jq -r --arg bot "$BMAD_PR_REVIEWER_BOT_REGEX" '
      [ .[]
        | select(.user.type == "Bot")
        | select(.user.login | test($bot; "i"))
        | select(.state == "APPROVED")
      ] | length > 0'
}

# reviewer_completed <pr> <sha> <since_iso> → rc 0 when a review completed.
reviewer_completed() {
  local pr=$1 sha=$2 since=${3:-}
  case "${BMAD_PR_REVIEWER_COMPLETION:-check-run}" in
    check-run)
      [[ "$(reviewer_check_state "$sha")" == "completed" ]]
      ;;
    bot-review)
      local n
      n="$(reviewer_reviews "$pr" |
        jq -r --arg bot "$BMAD_PR_REVIEWER_BOT_REGEX" --arg since "$since" '
          [ .[]
            | select(.user.type == "Bot")
            | select(.user.login | test($bot; "i"))
            | select($since == "" or .submitted_at > $since)
          ] | length')"
      [[ "$n" -gt 0 ]]
      ;;
    *)
      refuse "invalid BMAD_PR_REVIEWER_COMPLETION: $BMAD_PR_REVIEWER_COMPLETION"
      ;;
  esac
}

# reviewer_wait <pr> <sha> <timeout_sec> → prints completed|absent|timeout.
# rc 0 for completed, 1 otherwise. "absent" = no lifecycle signal appeared
# within the grace window (reviewer not installed, draft skipped, ignored).
reviewer_wait() {
  local pr=$1 sha=$2 timeout=$3 since=${4:-}
  local deadline=$(($(epoch) + timeout))
  local grace_deadline=$(($(epoch) + 180))
  local interval="${BMAD_PR_POLL_INTERVAL:-15}"
  local seen_signal=false state
  while :; do
    if reviewer_completed "$pr" "$sha" "$since"; then
      printf 'completed\n'
      return 0
    fi
    if [[ "${BMAD_PR_REVIEWER_COMPLETION:-check-run}" == "check-run" ]]; then
      state="$(reviewer_check_state "$sha")"
      [[ "$state" == "queued" || "$state" == "in_progress" ]] && seen_signal=true
    fi
    if [[ "$seen_signal" == false ]] && (($(epoch) >= grace_deadline)); then
      printf 'absent\n'
      return 1
    fi
    (($(epoch) >= deadline)) && {
      printf 'timeout\n'
      return 1
    }
    sleep "$interval"
    ((interval < 60)) && interval=$((interval * 2))
  done
}

# reviewer_unresolved_threads <pr> → JSON array of
# {id, path, line, author, body} for unresolved, non-outdated bot threads.
reviewer_unresolved_threads() {
  local pr=$1 owner name slug
  slug="$(repo_slug)"
  owner="${slug%%/*}"
  name="${slug##*/}"
  gh api graphql --paginate \
    -f owner="$owner" -f repo="$name" -F pr="$pr" \
    -f query='
      query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
        repository(owner: $owner, name: $repo) {
          pullRequest(number: $pr) {
            reviewThreads(first: 50, after: $endCursor) {
              pageInfo { hasNextPage endCursor }
              nodes {
                id
                isResolved
                isOutdated
                path
                line
                comments(first: 1) {
                  nodes { author { login } body }
                }
              }
            }
          }
        }
      }' 2>/dev/null |
    jq -s --arg bot "$BMAD_PR_REVIEWER_BOT_REGEX" '
      [ .[].data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false and .isOutdated == false)
        | select((.comments.nodes[0].author.login // "") | test($bot; "i"))
        | { id,
            path,
            line,
            author: .comments.nodes[0].author.login,
            body: (.comments.nodes[0].body // "") }
      ]' || printf '[]\n'
}

# reviewer_resolve_threads <thread-id>... — batched aliased mutations.
reviewer_resolve_threads() {
  local -a ids=("$@")
  local batch_size=20 i j mutation id
  for ((i = 0; i < ${#ids[@]}; i += batch_size)); do
    mutation="mutation {"
    for ((j = i; j < i + batch_size && j < ${#ids[@]}; j++)); do
      id="${ids[$j]}"
      [[ "$id" =~ ^[A-Za-z0-9_=-]+$ ]] || die "suspicious thread id: $id"
      mutation+=" t$j: resolveReviewThread(input: {threadId: \"$id\"}) { thread { isResolved } }"
    done
    mutation+=" }"
    gh api graphql -f query="$mutation" >/dev/null ||
      warn "some thread resolutions in batch starting at $i failed"
  done
}

# reviewer_trigger <pr> [extra context] — post the re-review comment.
reviewer_trigger() {
  local pr=$1 extra=${2:-}
  local body="$BMAD_PR_REVIEWER_TRIGGER${extra:+ $extra}"
  gh pr comment "$pr" --body "$body" >/dev/null || die "gh pr comment failed"
}
