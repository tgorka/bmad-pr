# shellcheck shell=bash
# Reviewer profile: cubic.dev (https://docs.cubic.dev).
# Fills gaps only — env vars and _bmad/bmad-pr/config.env override every field.
#
# Notes (verified against cubic docs + the cubic-loop skill):
# - Bot login matches ^cubic (GraphQL logins come WITHOUT the "[bot]" suffix).
# - Lifecycle is visible as a GitHub check run named ^cubic (case-insensitive).
# - Any comment mentioning the bot handle re-triggers a review; cubic dedupes
#   triggers on an unchanged, already-reviewed SHA.
# - "PR score: N/10" is NOT native cubic — it is injected via
#   reviews.custom_instructions in cubic.yaml. Missing score after a completed
#   review means that instruction is absent in the target repo.

reviewer_profile() {
  : "${BMAD_PR_REVIEWER_BOT_REGEX:=^cubic}"
  : "${BMAD_PR_REVIEWER_CHECK_REGEX:=^cubic}"
  : "${BMAD_PR_REVIEWER_TRIGGER:=@cubic-dev re-review}"
  : "${BMAD_PR_REVIEWER_COMPLETION:=check-run}"
  : "${BMAD_PR_SCORE_REGEX:=PR score: ([0-9]+)/10}"
}
