#!/usr/bin/env bash
# api — share of wall-clock time spent waiting on the API.
#
# High is not bad in itself; it means the session is model-bound rather than
# tool-bound, which is what you want to know before chasing latency elsewhere.
segment_api() {
  local api total pct color
  api=$(sl_int api_duration_ms 0)
  total=$(sl_int duration_ms 0)
  [ "$total" -gt 0 ] && [ "$api" -gt 0 ] || return 1
  pct=$((api * 100 / total))
  [ "$pct" -gt 0 ] || return 1
  [ "$pct" -gt 100 ] && pct=100
  color=$(sl_threshold_color "$pct" 50 80)
  sl_paint dim 'api '
  sl_paint "$color" "${pct}%"
}
