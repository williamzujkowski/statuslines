#!/usr/bin/env bash
# effort — the reasoning effort level.
#
# Absent when the model has no effort parameter, which is a real state and not
# an error; the segment simply renders nothing.
segment_effort() {
  local level color
  sl_has effort || return 1
  level=$(sl_get effort)
  case "$level" in
    low) color=${SL_THEME_effort_low_color:-dim} ;;
    medium) color=${SL_THEME_effort_medium_color:-green} ;;
    high) color=${SL_THEME_effort_high_color:-yellow} ;;
    xhigh | max) color=${SL_THEME_effort_max_color:-red} ;;
    *) color=dim ;;
  esac
  sl_paint "$color" "e:${level}"
}
