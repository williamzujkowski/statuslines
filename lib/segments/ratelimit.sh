#!/usr/bin/env bash
# ratelimit — Anthropic usage-window consumption.
#
# Present on Pro/Max plans only, and only after the first API response, so
# absence is normal and silent. used_percentage is a float (values like 23.5),
# which is why this reads it with sl_num rather than sl_int.
#
# Also reports pace: consumption minus the share of the window that has already
# elapsed. Positive means burning faster than the window replenishes, which is
# the number that actually predicts running out.
segment_ratelimit() {
  local shown=0
  if sl_has rl5_pct; then
    _sl_ratelimit_window rl5 "${SL_THEME_ratelimit_5h_label:-5h}" 300
    shown=1
  fi
  if [ "${SL_THEME_ratelimit_show_7d:-0}" = "1" ] && sl_has rl7_pct; then
    [ "$shown" -eq 1 ] && printf ' '
    _sl_ratelimit_window rl7 "${SL_THEME_ratelimit_7d_label:-7d}" 10080
    shown=1
  fi
  [ "$shown" -eq 1 ] || return 1
  return 0
}

# _sl_ratelimit_window <field_prefix> <label> <window_minutes>
_sl_ratelimit_window() {
  local prefix=$1 label=$2 window_min=$3
  local pct reset now remaining_min elapsed_min elapsed_pct pace color threshold

  pct=$(sl_num "${prefix}_pct" 0)
  [ "$pct" -lt 0 ] && pct=0
  [ "$pct" -gt 100 ] && pct=100

  color=$(sl_threshold_color "$pct" \
    "${SL_THEME_ratelimit_warn:-70}" "${SL_THEME_ratelimit_crit:-90}")
  sl_paint dim "${label} "
  sl_paint "$color" "${pct}%"

  sl_has "${prefix}_reset" || return 0

  # resets_at is epoch SECONDS, not milliseconds. Treating it as milliseconds
  # puts the reset in 1970 and the countdown never moves.
  reset=$(sl_num "${prefix}_reset" 0)
  now=$(sl_now)
  [ "$reset" -gt "$now" ] || return 0
  remaining_min=$(((reset - now) / 60))

  if [ "${SL_THEME_ratelimit_show_reset:-1}" = "1" ]; then
    if [ "$remaining_min" -ge 60 ]; then
      sl_paint dim "$(printf '(%dh%dm)' "$((remaining_min / 60))" "$((remaining_min % 60))")"
    else
      sl_paint dim "$(printf '(%dm)' "$remaining_min")"
    fi
  fi

  [ "${SL_THEME_ratelimit_pace:-1}" = "1" ] || return 0
  [ "$window_min" -gt 0 ] || return 0

  elapsed_min=$((window_min - remaining_min))
  [ "$elapsed_min" -lt 0 ] && elapsed_min=0
  elapsed_pct=$((elapsed_min * 100 / window_min))
  pace=$((pct - elapsed_pct))
  threshold=${SL_THEME_ratelimit_pace_threshold:-5}

  if [ "$pace" -ge "$threshold" ]; then
    printf ' '
    sl_paint red "over${pace}"
  elif [ "$pace" -le "$((0 - threshold))" ]; then
    printf ' '
    sl_paint green "under$((0 - pace))"
  fi
  return 0
}
