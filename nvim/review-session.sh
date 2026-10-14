#!/usr/bin/env bash
# Keep the launcher alive until the editor and any requested cleanup finish.
set -uo pipefail
review_nvim=$1
review_record=$2
review_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export DIFFVIEW_REVIEW_RECORD="$review_record"
export DIFFVIEW_REVIEW_OWNER=$$
cd "$review_root" || exit 1

release_review() {
  "$review_nvim" -l "$review_root/review-session.lua" release "$review_record"
}
trap release_review EXIT

"$review_nvim" -c "lua require('config.review_session').start(vim.env.DIFFVIEW_REVIEW_RECORD, vim.env.DIFFVIEW_REVIEW_OWNER)"
review_status=$?
if [[ $review_status -eq 0 ]]; then
  "$review_nvim" -l "$review_root/review-session.lua" cleanup "$review_record"
  review_status=$?
fi
if [[ $review_status -ne 0 ]]; then
  printf '\nReview closed with an error. Cleanup stopped; see the result above.\nPress Enter to close this pane.\n'
  IFS= read -r _ || true
fi
exit "$review_status"
