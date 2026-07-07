# shellcheck shell=bash
# Provider-agnostic reviewer engine. A provider profile (lib/reviewers/*.sh)
# supplies: BMAD_PR_REVIEWER_BOT_REGEX, BMAD_PR_REVIEWER_TRIGGER,
# BMAD_PR_REVIEWER_CHECK_REGEX (may be empty), BMAD_PR_REVIEWER_COMPLETION
# (check-run | bot-review), BMAD_PR_SCORE_REGEX (may be empty).
#
# All GitHub access goes through gh. gh api --jq cannot bind variables, so
# results are piped through real jq. REST/GraphQL pagination emits one JSON
# document per page — always merge with `jq -s`.

# Base repo for all GitHub queries. With an `upstream` remote (fork
# workflow, DW-3) the base is upstream; otherwise gh resolves it from the
# working directory.
repo_slug() {
  if [[ -z "${_BMAD_PR_REPO_SLUG:-}" ]]; then
    if git remote get-url upstream >/dev/null 2>&1; then
      _BMAD_PR_REPO_SLUG="$(remote_slug upstream)" ||
        refuse "cannot parse the upstream remote URL into owner/repo — fix the remote (git remote set-url upstream <forge-url>) or remove it"
    else
      _BMAD_PR_REPO_SLUG="$(gh repo view --json owner,name \
        --jq '"\(.owner.login)/\(.name)"')" || die "gh repo view failed"
    fi
  fi
  printf '%s\n' "$_BMAD_PR_REPO_SLUG"
}

# reviewer_check_latest <sha> → the newest matching check run (JSON), or null.
# Paginated (a busy commit can have >1 page of check runs). Runs without
# started_at (queued) sort as NEWEST — a freshly queued attempt must win
# over an older completed run for the same SHA.
reviewer_check_latest() {
  local sha=$1
  if [[ -z "${BMAD_PR_REVIEWER_CHECK_REGEX:-}" ]]; then
    printf 'null\n'
    return 0
  fi
  gh api --paginate "repos/$(repo_slug)/commits/$sha/check-runs" 2>/dev/null |
    jq -s --arg re "$BMAD_PR_REVIEWER_CHECK_REGEX" '
      [.[].check_runs[] | select(.name | test($re; "i"))]
      | sort_by(.started_at // "9999-12-31T23:59:59Z") | last // null' ||
    printf 'null\n'
}

# reviewer_check_state <sha> → queued|in_progress|completed|missing
reviewer_check_state() {
  reviewer_check_latest "$1" | jq -r '.status // "missing"'
}

# All PR reviews (merged across pages) → JSON array. Fails fast on API
# errors — treating them as "no reviews" would let watch/ingest report a
# false green.
reviewer_reviews() {
  local pr=$1 out
  out="$(gh api --paginate "repos/$(repo_slug)/pulls/$pr/reviews" 2>/dev/null)" ||
    die "gh api failed listing reviews for PR $pr (auth? network? rate limit?)"
  jq -s 'add // []' <<<"$out"
}

# reviewer_latest_score <pr> [head_sha] → the captured score number, or
# empty. When head_sha is given, only reviews of that commit count — a
# score from an earlier revision must not green-light freshly pushed code.
reviewer_latest_score() {
  local pr=$1 sha=${2:-} raw
  [[ -n "${BMAD_PR_SCORE_REGEX:-}" ]] || return 0
  raw="$(reviewer_reviews "$pr" |
    jq -r --arg bot "$BMAD_PR_REVIEWER_BOT_REGEX" --arg re "$BMAD_PR_SCORE_REGEX" \
      --arg sha "$sha" '
      [ .[]
        | select(.user.type == "Bot")
        | select(.user.login | test($bot; "i"))
        | select($sha == "" or .commit_id == $sha)
        | select(.body | test($re))
      ] | sort_by(.submitted_at) | last
      | if . == null then empty
        else (.body | match($re) | .captures[0].string)
        end')"
  [[ -z "$raw" ]] && return 0
  # Downstream comparisons are bash integer arithmetic — truncate decimals
  # (rounding down biases toward "findings", the safe direction) and drop
  # anything non-numeric a generic provider regex might capture.
  if [[ "$raw" =~ ^[0-9]+ ]]; then
    printf '%s\n' "${BASH_REMATCH[0]}"
  else
    warn "ignoring non-numeric reviewer score: '$raw'"
  fi
}

# reviewer_approved <pr> [head_sha] → prints true|false. Scoped to the
# current head when given, and based on the reviewer's LATEST review state —
# an approval superseded by a later non-approval review no longer counts.
reviewer_approved() {
  local pr=$1 sha=${2:-}
  reviewer_reviews "$pr" |
    jq -r --arg bot "$BMAD_PR_REVIEWER_BOT_REGEX" --arg sha "$sha" '
      [ .[]
        | select(.user.type == "Bot")
        | select(.user.login | test($bot; "i"))
        | select($sha == "" or .commit_id == $sha)
      ] | sort_by(.submitted_at) | last
      | ((.state // "") == "APPROVED")'
}

# reviewer_review_count <pr> [head_sha] → number of bot reviews (scoped to a
# head when given). Distinguishes "reviewer produced output but no score"
# from "reviewer has not reviewed this commit at all".
reviewer_review_count() {
  local pr=$1 sha=${2:-}
  reviewer_reviews "$pr" |
    jq -r --arg bot "$BMAD_PR_REVIEWER_BOT_REGEX" --arg sha "$sha" '
      [ .[]
        | select(.user.type == "Bot")
        | select(.user.login | test($bot; "i"))
        | select($sha == "" or .commit_id == $sha)
      ] | length'
}

# reviewer_completed <pr> <sha> <since_iso> → rc 0 when a review completed.
reviewer_completed() {
  local pr=$1 sha=$2 since=${3:-}
  case "${BMAD_PR_REVIEWER_COMPLETION:-check-run}" in
    check-run)
      local run completed_at
      run="$(reviewer_check_latest "$sha")"
      [[ "$(jq -r '.status // "missing"' <<<"$run")" == "completed" ]] || return 1
      # A run that completed BEFORE this cycle started is a previous attempt
      # on the same SHA (typical right after `rereview --resolve-addressed`)
      # — not this cycle's completion. ISO-8601 compares lexicographically.
      if [[ -n "$since" ]]; then
        completed_at="$(jq -r '.completed_at // ""' <<<"$run")"
        [[ -n "$completed_at" && "$completed_at" > "$since" ]] || return 1
      fi
      return 0
      ;;
    bot-review)
      # Scope to the current head AND to this cycle: a late-landing review
      # of an OLDER commit submitted after `since` must not complete the
      # wait for the freshly pushed SHA.
      local n
      n="$(reviewer_reviews "$pr" |
        jq -r --arg bot "$BMAD_PR_REVIEWER_BOT_REGEX" --arg since "$since" \
          --arg sha "$sha" '
          [ .[]
            | select(.user.type == "Bot")
            | select(.user.login | test($bot; "i"))
            | select($sha == "" or .commit_id == $sha)
            | select($since == "" or .submitted_at > $since)
          ] | length')"
      [[ "$n" -gt 0 ]]
      ;;
    *)
      refuse "invalid BMAD_PR_REVIEWER_COMPLETION: $BMAD_PR_REVIEWER_COMPLETION"
      ;;
  esac
}

# reviewer_wait <pr> <sha> <timeout_sec> [since_iso] → prints
# completed|absent|timeout. rc 0 for completed, 1 otherwise. "absent" = no
# lifecycle signal within the grace window (reviewer not installed, draft
# skipped, ignored). Only check-run mode has a lifecycle signal to miss —
# bot-review providers (no check run) get the full timeout, not the grace.
reviewer_wait() {
  local pr=$1 sha=$2 timeout=$3 since=${4:-}
  local deadline grace_deadline
  deadline=$(($(epoch) + timeout))
  grace_deadline=$(($(epoch) + 180))
  ((grace_deadline > deadline)) && grace_deadline=$deadline
  local interval="${BMAD_PR_POLL_INTERVAL:-15}"
  local seen_signal=false state
  while :; do
    if reviewer_completed "$pr" "$sha" "$since"; then
      printf 'completed\n'
      return 0
    fi
    if [[ "${BMAD_PR_REVIEWER_COMPLETION:-check-run}" == "check-run" ]]; then
      state="$(reviewer_check_state "$sha")"
      # Any documented non-completed active status is a lifecycle signal.
      case "$state" in
        queued | in_progress | requested | waiting | pending) seen_signal=true ;;
      esac
      if [[ "$seen_signal" == false ]] && (($(epoch) >= grace_deadline)); then
        printf 'absent\n'
        return 1
      fi
    fi
    local now remaining
    now="$(epoch)"
    ((now >= deadline)) && {
      printf 'timeout\n'
      return 1
    }
    # Never sleep past the deadline (backoff can exceed the remaining time).
    remaining=$((deadline - now))
    if ((interval < remaining)); then
      sleep "$interval"
    else
      sleep "$remaining"
    fi
    ((interval < 60)) && interval=$((interval * 2))
  done
}

# reviewer_unresolved_threads <pr> → JSON array of
# {id, path, line, author, body} for unresolved, non-outdated bot threads.
reviewer_unresolved_threads() {
  local pr=$1 owner name slug out
  slug="$(repo_slug)"
  owner="${slug%%/*}"
  name="${slug##*/}"
  out="$(gh api graphql --paginate \
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
      }' 2>/dev/null)" ||
    die "gh api graphql failed listing review threads for PR $pr (auth? network? rate limit?)"
  jq -s --arg bot "$BMAD_PR_REVIEWER_BOT_REGEX" '
      [ .[].data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false and .isOutdated == false)
        | select((.comments.nodes[0].author.login // "") | test($bot; "i"))
        | { id,
            path,
            line,
            author: .comments.nodes[0].author.login,
            body: (.comments.nodes[0].body // "") }
      ]' <<<"$out"
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
  gh pr comment "$pr" --repo "$(repo_slug)" --body "$body" >/dev/null ||
    die "gh pr comment failed"
}
