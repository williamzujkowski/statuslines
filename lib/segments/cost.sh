#!/usr/bin/env bash
# cost — session spend.
#
# This is Claude Code's own client-side estimate, and it resets to zero on
# /clear. It is not a bill.
segment_cost() {
  local raw dollars out
  sl_numeric cost_usd || return 1
  raw=$(sl_get cost_usd 0)
  dollars=$(sl_num cost_usd 0)

  # Adaptive precision: cents are noise at $40 and everything at $0.004.
  if [ "$dollars" -ge 1 ]; then
    out=$(printf '$%.2f' "$raw" 2>/dev/null) || out="\$${dollars}"
  else
    out=$(printf '$%.4f' "$raw" 2>/dev/null) || out="\$0"
  fi

  sl_paint "${SL_THEME_cost_color:-yellow}" "$out"
}
