#!/usr/bin/env bash
# tokens — input and output tokens for the latest response, in thousands.
#
# These are per-response, not cumulative (Claude Code 2.1.132 changed this), so
# they describe the last turn rather than the whole session.
segment_tokens() {
  local in_t out_t
  in_t=$(sl_int ctx_in 0)
  out_t=$(sl_int ctx_out 0)
  [ "$in_t" -gt 0 ] || [ "$out_t" -gt 0 ] || return 1
  sl_paint dim 'tok '
  sl_paint "${SL_THEME_tokens_color:-cyan}" "$((in_t / 1000))k/$((out_t / 1000))k"
}
