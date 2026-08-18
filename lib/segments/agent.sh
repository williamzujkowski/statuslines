#!/usr/bin/env bash
# agent — the named agent driving this session, when there is one.
segment_agent() {
  sl_has agent_name || return 1
  sl_paint "${SL_THEME_agent_color:-bright_magenta}" "[$(sl_get agent_name)]"
}
