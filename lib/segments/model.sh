#!/usr/bin/env bash
# model — the model display name, plus the modes that change what it does.
#
# fast_mode and thinking are shown as short text labels rather than as colors,
# because a mode the user cannot see is a mode they will misattribute
# (docs/CODING-STANDARDS.md §8).
segment_model() {
  sl_has model_name || return 1
  sl_paint "${SL_THEME_model_color:-magenta}" "$(sl_get model_name)"

  [ "${SL_THEME_model_show_modes:-1}" = "1" ] || return 0

  if sl_bool fast_mode; then
    printf ' '
    sl_paint "${SL_THEME_model_fast_color:-cyan}" 'fast'
  fi
  # Thinking defaults on, so only its absence is worth the columns.
  if sl_has thinking && ! sl_bool thinking; then
    printf ' '
    sl_paint dim 'nothink'
  fi
  return 0
}
