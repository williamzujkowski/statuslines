#!/usr/bin/env bash
# vim — the current vim mode, when vim mode is enabled.
#
# Claude Code draws its own "-- INSERT --" unless hideVimModeIndicator is set,
# so enabling this segment without setting that option shows the mode twice.
segment_vim() {
  local mode color
  sl_has vim_mode || return 1
  mode=$(sl_get vim_mode)
  case "$mode" in
    INSERT) color=green ;;
    "VISUAL" | "VISUAL LINE") color=yellow ;;
    *) color=dim ;;
  esac
  sl_paint "$color" "${mode}"
}
