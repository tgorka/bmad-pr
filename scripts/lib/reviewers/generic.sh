# shellcheck shell=bash
# Reviewer profile: generic — integrate any comment-triggered PR reviewer
# (CodeRabbit, Greptile, ...) purely through configuration. Set at minimum
# BMAD_PR_REVIEWER_BOT_REGEX and BMAD_PR_REVIEWER_TRIGGER in the environment
# or in _bmad/bmad-pr/config.env. Examples:
#
#   CodeRabbit: BOT_REGEX='^coderabbitai'  TRIGGER='@coderabbitai review'
#               COMPLETION=bot-review      (CodeRabbit posts no check run)
#   Greptile:   BOT_REGEX='^greptile'      TRIGGER='@greptileai'
#               CHECK_REGEX='^greptile'    COMPLETION=check-run

reviewer_profile() {
  [[ -n "${BMAD_PR_REVIEWER_BOT_REGEX:-}" ]] ||
    refuse "generic reviewer needs BMAD_PR_REVIEWER_BOT_REGEX (bot login regex)"
  [[ -n "${BMAD_PR_REVIEWER_TRIGGER:-}" ]] ||
    refuse "generic reviewer needs BMAD_PR_REVIEWER_TRIGGER (re-review comment)"
  : "${BMAD_PR_REVIEWER_COMPLETION:=bot-review}"
  : "${BMAD_PR_REVIEWER_CHECK_REGEX:=}"
  : "${BMAD_PR_SCORE_REGEX:=}"
}
