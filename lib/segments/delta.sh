#!/usr/bin/env bash
# delta — lines added and removed this session.
segment_delta() {
  local added removed
  added=$(sl_int lines_added 0)
  removed=$(sl_int lines_removed 0)
  [ "$added" -gt 0 ] || [ "$removed" -gt 0 ] || return 1
  sl_paint "${SL_THEME_delta_add_color:-green}" "+${added}"
  [ "$removed" -gt 0 ] && sl_paint "${SL_THEME_delta_del_color:-red}" "/-${removed}"
  return 0
}
