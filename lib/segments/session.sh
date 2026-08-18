#!/usr/bin/env bash
# session — the session name, when the user named it.
#
# Absent for auto-generated default names, so this segment is quiet in most
# sessions and identifying in the ones where it matters.
segment_session() {
  sl_has session_name || return 1
  sl_paint "${SL_THEME_session_color:-cyan}" "$(sl_get session_name)"
}
