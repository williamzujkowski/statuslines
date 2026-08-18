#!/usr/bin/env bash
# duration — wall-clock time since the session started.
segment_duration() {
  local ms min hr out
  ms=$(sl_int duration_ms 0)
  [ "$ms" -gt 0 ] || return 1
  min=$((ms / 60000))
  if [ "$min" -ge 60 ]; then
    hr=$((min / 60))
    out="${hr}h$((min % 60))m"
  else
    out="${min}m"
  fi
  sl_paint "${SL_THEME_duration_color:-cyan}" "$out"
}
