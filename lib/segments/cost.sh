#!/usr/bin/env bash
# cost — session spend.
#
# Claude Code's own client-side estimate, and it resets to zero on /clear.
# It is not a bill.
#
# Rounded to two or three significant figures rather than to the cent. Cents on
# a hundred-dollar total are false precision, and worse, the jitter shifts every
# column to the right of this field on every single render.
segment_cost() {
  local raw dollars out
  sl_numeric cost_usd || return 1
  raw=$(sl_get cost_usd 0)
  dollars=$(sl_num cost_usd 0)

  if [ "$dollars" -ge 1000 ]; then
    out=$(printf '$%d.%dk' "$((dollars / 1000))" "$(((dollars % 1000) / 100))")
  elif [ "$dollars" -ge 10 ]; then
    out=$(printf '$%d' "$dollars")
  elif [ "$dollars" -ge 1 ]; then
    out=$(printf '$%.2f' "$raw" 2>/dev/null) || out="\$${dollars}"
  else
    out=$(printf '$%.2f' "$raw" 2>/dev/null) || out="\$0"
  fi

  sl_paint "${SL_THEME_cost_color:-none}" "$(printf '%*s' "${SL_THEME_cost_width:-0}" "$out")"
}
