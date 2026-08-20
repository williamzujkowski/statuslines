#!/usr/bin/env bash
# ratelimit — Anthropic usage-window consumption.
#
# Dark cockpit: this renders NOTHING while consumption is comfortable.
#
# A field that reads "0%" all day trains the eye to skip that region, and it
# will still be skipped on the day it reads 94%. Aircraft annunciators, road
# vehicle telltales and high-performance HMI practice all converge on the same
# rule — the indicator is absent when normal — and the reported payoff is a
# large improvement in noticing the abnormal case. The threshold is
# `ratelimit_show_above`; set it to 0 to show the window unconditionally.
#
# Present on Pro/Max plans only and only after the first API response, so
# absence is doubly normal. used_percentage is a float, hence sl_num not sl_int.
segment_ratelimit() {
  local shown=0
  if sl_has rl5_pct; then
    _sl_ratelimit_window rl5 "${SL_THEME_ratelimit_5h_label:-5h}" 300 0 && shown=1
  fi
  if [ "${SL_THEME_ratelimit_show_7d:-0}" = "1" ] && sl_has rl7_pct; then
    # The separator is passed in rather than printed here, because the window
    # can still decline to render at the show_above floor — and the common
    # state is exactly that: the five-hour window hot while the weekly one is
    # quiet. Printing the space first left a stray column in the line.
    _sl_ratelimit_window rl7 "${SL_THEME_ratelimit_7d_label:-7d}" 10080 "$shown" && shown=1
  fi
  [ "$shown" -eq 1 ] || return 1
  return 0
}

# _sl_ratelimit_window <field_prefix> <label> <window_minutes> <lead_space>
#
# Emits nothing at all when the value is below the show_above floor, including
# the leading separator — the caller cannot know in advance whether this window
# will render.
_sl_ratelimit_window() {
  local prefix=$1 label=$2 window_min=$3 lead=${4:-0}
  local pct reset now remaining state marker floor

  pct=$(sl_num "${prefix}_pct" 0)
  [ "$pct" -lt 0 ] && pct=0
  [ "$pct" -gt 100 ] && pct=100

  floor=${SL_THEME_ratelimit_show_above:-0}
  case "$floor" in '' | *[!0-9]*) floor=0 ;; esac
  [ "$pct" -ge "$floor" ] || return 1

  [ "$lead" -eq 1 ] && printf ' '

  sl_threshold_default ratelimit_crit
  state=$(sl_state "$pct" "${SL_THEME_ratelimit_warn:-70}" "$_SL_THRESHOLD_VALUE")
  state=$(sl_state_cap "$prefix" "$state")
  marker=$(sl_state_marker "$state")

  sl_paint dim "${label} "
  sl_state_paint "$state" "${pct}%${marker}"

  sl_has "${prefix}_reset" || return 0
  [ "${SL_THEME_ratelimit_show_reset:-1}" = "1" ] || return 0

  # resets_at is epoch SECONDS. Treating it as milliseconds puts the reset in
  # 1970 and the countdown never moves.
  reset=$(sl_num "${prefix}_reset" 0)
  now=$(sl_now)
  [ "$reset" -gt "$now" ] || return 0
  remaining=$(((reset - now) / 60))

  # Time REMAINING, at a precision proportional to urgency: days out needs no
  # hours, hours out needs no minutes, and only the last hour needs minutes.
  printf ' '
  if [ "$remaining" -ge 2880 ]; then
    sl_paint dim "$(printf 'resets %dd' "$((remaining / 1440))")"
  elif [ "$remaining" -ge 60 ]; then
    sl_paint dim "$(printf 'resets %dh' "$((remaining / 60))")"
  else
    sl_state_paint "$state" "$(printf 'resets %dm' "$remaining")"
  fi

  # Pace: consumption minus the share of the window already elapsed. Positive
  # means burning faster than the window replenishes, which is the number that
  # actually predicts running out. Shown only when off-pace by more than the
  # threshold — an "on pace" indicator every render is noise.
  [ "${SL_THEME_ratelimit_pace:-1}" = "1" ] || return 0
  [ "$window_min" -gt 0 ] || return 0

  local elapsed_min elapsed_pct pace threshold
  elapsed_min=$((window_min - remaining))
  [ "$elapsed_min" -lt 0 ] && elapsed_min=0
  elapsed_pct=$((elapsed_min * 100 / window_min))
  pace=$((pct - elapsed_pct))
  threshold=${SL_THEME_ratelimit_pace_threshold:-15}
  case "$threshold" in '' | *[!0-9]*) threshold=15 ;; esac

  if [ "$pace" -ge "$threshold" ]; then
    printf ' '
    sl_state_paint watch "$(printf 'over pace %d%%' "$pace")"
  fi
  return 0
}
