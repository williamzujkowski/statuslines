#!/usr/bin/env bash
# tokens — input and output tokens for the latest response.
#
# Per-response, not cumulative (Claude Code 2.1.132 changed this), so they
# describe the last turn rather than the session.
#
# A value under a thousand renders as a dash, not as "0k". A credible zero in
# place of an unknown is the failure mode users do not notice, which is exactly
# why it has to look different from a real zero.
segment_tokens() {
  local in_t out_t in_s out_s unk
  in_t=$(sl_int ctx_in 0)
  out_t=$(sl_int ctx_out 0)
  [ "$in_t" -gt 0 ] || [ "$out_t" -gt 0 ] || return 1
  unk=${SL_THEME_unknown_glyph:---}

  if [ "$in_t" -ge 1000 ]; then in_s="$((in_t / 1000))k"; elif [ "$in_t" -gt 0 ]; then in_s="$in_t"; else in_s=$unk; fi
  if [ "$out_t" -ge 1000 ]; then out_s="$((out_t / 1000))k"; elif [ "$out_t" -gt 0 ]; then out_s="$out_t"; else out_s=$unk; fi

  sl_paint dim 'tok '
  sl_paint "${SL_THEME_tokens_color:-none}" "${in_s}/${out_s}"
}
