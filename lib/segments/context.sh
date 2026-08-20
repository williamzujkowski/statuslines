#!/usr/bin/env bash
# context — how full the context window is.
#
# The primary metric on the line: it has a hard ceiling, it moves every turn,
# and hitting it changes what the user does. It is the one segment that gets a
# bar, because a bar is only worth its columns when it is scarce.
#
# used_percentage is null before the first API call and right after /compact.
# That is "unknown", not 0%, and rendering it as 0% is the confidently wrong
# number AGENTS.md §4.1 exists to prevent.
segment_context() {
  local pct label state marker size

  label=${SL_THEME_context_label:-ctx}

  size=$(sl_int ctx_size 0)
  [ "$size" -gt 200000 ] && [ "${SL_THEME_context_extended_mark:-1}" = "1" ] && label="${label}+"

  if ! sl_numeric ctx_pct; then
    sl_paint dim "${label} "
    sl_paint "${SL_THEME_context_unknown_color:-dim}" "${SL_THEME_unknown_glyph:---}"
    return 0
  fi

  pct=$(sl_num ctx_pct 0)
  [ "$pct" -lt 0 ] && pct=0
  [ "$pct" -gt 100 ] && pct=100

  state=$(sl_state "$pct" "${SL_THEME_context_warn:-70}" "${SL_THEME_context_crit:-90}")
  state=$(sl_state_cap context "$state")
  marker=$(sl_state_marker "$state")

  sl_paint dim "${label} "
  # Percent padded to a fixed width so the fields to its right keep their
  # column as the value moves. A number that shifts its neighbours on every
  # render cannot be found by position, only by reading.
  sl_state_paint "$state" "$(printf '%*d%%%s' "$(sl_theme_int pct_width 0 10)" "$pct" "$marker")"

  if [ "${SL_THEME_context_bar:-0}" = "1" ]; then
    printf ' '
    sl_state_paint "$state" "$(_sl_bar "$pct" "$(sl_theme_int context_bar_width 10 60)" \
      "${SL_THEME_context_bar_full:-#}" "${SL_THEME_context_bar_empty:-.}")"
  fi

  # exceeds_200k_tokens uses a fixed 200k threshold and includes output tokens,
  # so on a 1M model it can fire while used_percentage is still low.
  if sl_bool exceeds_200k && [ "${SL_THEME_context_200k_mark:-1}" = "1" ]; then
    printf ' '
    sl_paint dim '200k+'
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
