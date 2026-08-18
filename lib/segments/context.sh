#!/usr/bin/env bash
# context — how full the context window is.
#
# used_percentage is null before the first API call and right after /compact.
# That is "unknown", not 0%, and rendering it as 0% is exactly the confidently
# wrong number AGENTS.md §4.1 exists to prevent. A wrong-typed value is treated
# the same way, which is why this gates on sl_numeric rather than sl_has.
segment_context() {
  local pct label color size

  label=${SL_THEME_context_label:-ctx}

  # An extended-context model gets a distinguishable label: 40% of 1M is a very
  # different situation from 40% of 200k.
  size=$(sl_int ctx_size 0)
  [ "$size" -gt 200000 ] && label="${label}+"

  if ! sl_numeric ctx_pct; then
    sl_paint dim "${label} "
    sl_paint "${SL_THEME_context_unknown_color:-dim}" '--'
    return 0
  fi

  pct=$(sl_num ctx_pct 0)
  [ "$pct" -lt 0 ] && pct=0
  [ "$pct" -gt 100 ] && pct=100

  color=$(sl_threshold_color "$pct" \
    "${SL_THEME_context_warn:-60}" "${SL_THEME_context_crit:-85}")

  sl_paint dim "${label} "
  sl_paint "$color" "${pct}%"

  # The bar is decoration; the number above is always printed, so the bar is
  # never the sole carrier of the value (docs/CODING-STANDARDS.md §8).
  if [ "${SL_THEME_context_bar:-0}" = "1" ]; then
    printf ' '
    sl_paint "$color" "$(_sl_bar "$pct" "${SL_THEME_context_bar_width:-10}" \
      "${SL_THEME_context_bar_full:-#}" "${SL_THEME_context_bar_empty:-.}")"
  fi

  # exceeds_200k_tokens uses a fixed 200k threshold and includes output tokens,
  # so on a 1M model it can fire while used_percentage is still low. Showing it
  # separately keeps both facts honest rather than picking one.
  if sl_bool exceeds_200k; then
    printf ' '
    sl_paint red '200k+'
  fi
  return 0
}

# _sl_bar <pct> <width> <full_char> <empty_char>
_sl_bar() {
  local pct=$1 width=$2 full=$3 empty=$4 filled i out=""
  case "$width" in '' | *[!0-9]*) width=10 ;; esac
  filled=$((pct * width / 100))
  i=1
  while [ "$i" -le "$width" ]; do
    if [ "$i" -le "$filled" ]; then out="${out}${full}"; else out="${out}${empty}"; fi
    i=$((i + 1))
  done
  printf '%s' "$out"
}
