#!/usr/bin/env bash
# burn — spend rate in dollars per hour.
#
# Derived, because the payload gives totals rather than a rate:
#   $/h = total_cost_usd * 3600000 / total_duration_ms
#
# Suppressed for the first minute of a session, where dividing a few cents by a
# few seconds produces an alarming and meaningless number.
segment_burn() {
  local ms cents rate color min_ms
  ms=$(sl_int duration_ms 0)
  min_ms=${SL_THEME_burn_min_ms:-60000}
  case "$min_ms" in '' | *[!0-9]*) min_ms=60000 ;; esac
  [ "$ms" -ge "$min_ms" ] || return 1

  # Integer math in cents keeps this free of bc and of float surprises.
  cents=$(printf '%.0f' "$(sl_get cost_usd 0)e2" 2>/dev/null) || return 1
  case "$cents" in '' | *[!0-9]*) return 1 ;; esac
  [ "$cents" -gt 0 ] || return 1

  rate=$((cents * 3600000 / ms)) # cents per hour
  color=$(sl_threshold_color "$rate" \
    "${SL_THEME_burn_warn:-500}" \
    "${SL_THEME_burn_crit:-1500}")

  sl_paint "$color" "$(printf '$%d.%02d/h' "$((rate / 100))" "$((rate % 100))")"
}
