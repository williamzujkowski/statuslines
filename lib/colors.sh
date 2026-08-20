#!/usr/bin/env bash
# colors.sh — the only file in this repository permitted to contain an escape
# sequence literal (CODING-STANDARDS §6.5).
#
# Themes name colors; segments ask for a named color; nothing else knows what
# an SGR code looks like. That indirection is what makes the `plain` theme and
# the NO_COLOR path testable instead of aspirational.
#
# Only the 16 standard SGR colors are offered. The terminal's own theme maps
# those to values the user can actually read, whereas a hardcoded 256-color or
# truecolor value can land invisibly close to their background
# (CODING-STANDARDS §8).

# sl_colors_init
# Decides once, per render, whether color is emitted at all. Honors NO_COLOR
# (https://no-color.org/) and an explicit STATUSLINE_COLOR=0|1 override.
#
# Note that stdout is a pipe here, never a TTY, so a `[ -t 1 ]` test would
# disable color in normal operation. That check is deliberately absent.
sl_colors_init() {
  _SL_CODE=""
  case "${STATUSLINE_COLOR-}" in
    0 | off | never)
      SL_COLOR_ENABLED=0
      return
      ;;
    1 | on | always)
      SL_COLOR_ENABLED=1
      return
      ;;
  esac

  if [ -n "${NO_COLOR-}" ]; then
    SL_COLOR_ENABLED=0
  else
    SL_COLOR_ENABLED=1
  fi
}

# sl_code <name>
# Sets _SL_CODE to the SGR sequence for a named color, or to the empty string.
#
# This sets a variable rather than printing because the printing version had to
# be called through `$(...)`, and a command substitution forks. At roughly
# fifteen painted fragments per render that was thirty forks spent on color
# alone — a third of the latency budget for no output (AGENTS.md §4.4).
#
# An unknown name yields no code rather than an error: a typo in a theme should
# cost the user a color, not the whole status line.
sl_code() {
  if [ "${SL_COLOR_ENABLED:-1}" -ne 1 ]; then
    _SL_CODE=""
    return 0
  fi
  case "$1" in
    reset) _SL_CODE=$'\033[0m' ;;
    bold) _SL_CODE=$'\033[1m' ;;
    dim) _SL_CODE=$'\033[2m' ;;
    italic) _SL_CODE=$'\033[3m' ;;
    underline) _SL_CODE=$'\033[4m' ;;
    reverse) _SL_CODE=$'\033[7m' ;;

    black) _SL_CODE=$'\033[30m' ;;
    red) _SL_CODE=$'\033[31m' ;;
    green) _SL_CODE=$'\033[32m' ;;
    yellow) _SL_CODE=$'\033[33m' ;;
    blue) _SL_CODE=$'\033[34m' ;;
    magenta) _SL_CODE=$'\033[35m' ;;
    cyan) _SL_CODE=$'\033[36m' ;;
    white) _SL_CODE=$'\033[37m' ;;

    bright_black | gray | grey) _SL_CODE=$'\033[90m' ;;
    bright_red) _SL_CODE=$'\033[91m' ;;
    bright_green) _SL_CODE=$'\033[92m' ;;
    bright_yellow) _SL_CODE=$'\033[93m' ;;
    bright_blue) _SL_CODE=$'\033[94m' ;;
    bright_magenta) _SL_CODE=$'\033[95m' ;;
    bright_cyan) _SL_CODE=$'\033[96m' ;;
    bright_white) _SL_CODE=$'\033[97m' ;;

    *) _SL_CODE="" ;;
  esac
}

# sl_color <name> — printing form, for callers that genuinely want a string.
sl_color() {
  sl_code "$1"
  printf '%s' "$_SL_CODE"
}

# sl_paint <color> <text>
# The standard way for a segment to emit colored text. Always closes with a
# reset so one segment can never bleed its attributes into the next.
sl_paint() {
  local color=$1
  shift
  if [ "${SL_COLOR_ENABLED:-1}" -eq 1 ] && [ -n "$color" ] && [ "$color" != "none" ]; then
    sl_code "$color"
    if [ -n "$_SL_CODE" ]; then
      printf '%s%s%s' "$_SL_CODE" "$*" $'\033[0m'
      return 0
    fi
  fi
  printf '%s' "$*"
}

# sl_threshold_color <value> <warn> <crit> [good_color] [warn_color] [crit_color]
# Shared ramp for the several segments that color a number by how alarming it
# is. Extracted at the third occurrence, per the rule of three.
#
# Color is never the only signal — every caller also prints the number itself
# (CODING-STANDARDS §8).
sl_threshold_color() {
  local value=$1 warn=$2 crit=$3
  local good=${4:-green} warning=${5:-yellow} critical=${6:-red}
  if [ "$value" -ge "$crit" ]; then
    printf '%s' "$critical"
  elif [ "$value" -ge "$warn" ]; then
    printf '%s' "$warning"
  else
    # `quiet = 1` suppresses the in-band colour entirely, so colour on the line
    # means "this needs you" rather than "this is a number".
    #
    # Colouring every healthy value is what produces the rainbow: with a dozen
    # segments each owning a hue, nothing stands out, and the one value that
    # actually left its band competes with eleven that did not. Absence of
    # colour is a stronger signal than green, and it costs nothing to read.
    if [ "${SL_THEME_quiet:-0}" = "1" ]; then
      printf 'none'
    else
      printf '%s' "$good"
    fi
  fi
}

# sl_strip_ansi <text>
# Removes SGR sequences so width can be measured. Pure parameter expansion —
# this runs once per line per render and a sed spawn here would be about a
# quarter of the whole latency budget.
sl_strip_ansi() {
  local text=$1 out="" rest
  while [ -n "$text" ]; do
    rest=${text#*$'\033['}
    if [ "$rest" = "$text" ]; then
      out+=$text
      break
    fi
    out+=${text%%$'\033['*}
    # Drop the parameter bytes and the final letter of the sequence.
    text=${rest#*m}
    if [ "$text" = "$rest" ]; then
      break
    fi
  done
  printf '%s' "$out"
}

# sl_width <text>
# Display width in columns, ignoring color.
#
# Known ceiling: counts characters, so East Asian wide characters and emoji are
# undercounted by one column each. Correct wcwidth handling needs a lookup
# table; tracked separately. Ordinary paths and branch names measure correctly.
sl_width() {
  local plain
  plain=$(sl_strip_ansi "$1")
  printf '%s' "${#plain}"
}

# ── State ladder ─────────────────────────────────────────────────────────
#
# One vocabulary for "how alarming is this number", so every segment escalates
# the same way and there is one place to audit it.
#
# The ladder deliberately changes a NON-COLOUR channel at every step, because
# in a 16-colour terminal the warn/critical axis cannot be made safe with hue:
# the palette belongs to the user's theme, red might sit next to yellow in it,
# and red/green deficiency affects roughly 8% of men. Hue is therefore the
# LAST channel added, never the first — WCAG 1.4.1.
#
#   normal    plain text, no marker        (and under `quiet`, no colour)
#   watch     yellow, marker `!`           value has left its normal band
#   crit      bold red, marker `!!`         value needs action now
#
# The marker escalates by repetition rather than by switching glyph, so the
# severity ordering is legible without a legend and stays pure ASCII.
#
# sl_state <value> <warn> <crit> — echoes normal | watch | crit
sl_state() {
  local value=$1 warn=$2 crit=$3
  if [ "$value" -ge "$crit" ]; then
    printf 'crit'
  elif [ "$value" -ge "$warn" ]; then
    printf 'watch'
  else
    printf 'normal'
  fi
}

# sl_threshold_default <name>
# Resolves a shared critical threshold for both segment rendering and owner
# selection. Keep the names allowlisted because the result is used in numeric
# comparisons on every render. Sets _SL_THRESHOLD_VALUE to avoid a fork at
# each call site.
sl_threshold_default() {
  case "$1" in
    context_crit) _SL_THRESHOLD_VALUE=${SL_THEME_context_crit:-90} ;;
    ratelimit_crit) _SL_THRESHOLD_VALUE=${SL_THEME_ratelimit_crit:-90} ;;
    *)
      _SL_THRESHOLD_VALUE=""
      return 1
      ;;
  esac
}

# sl_crit_owner
#
# Which single metric is allowed to render as critical this frame.
#
# Pop-out only works when the alarming thing is unique in its channel: three
# red tokens are worth less than one, which is why alarm-management practice
# treats floods as desensitising rather than as three times the warning. So at
# most one metric may show critical, and the rest degrade to watch.
#
# This is computed from the payload rather than counted as segments render,
# because each segment runs inside a command substitution and any counter it
# incremented would die with that subshell. Deriving it instead keeps the
# choice deterministic and identical no matter which segments a theme enables
# or what order they appear in.
#
# Priority is severity of consequence: running out of context ends the session,
# a spent five-hour window blocks the next few hours, the weekly window is the
# slowest to bite.
# _sl_segment_active <name> — is this segment in any line the theme declares?
#
# SL_ACTIVE_SEGMENTS is set by sl_render before any segment runs, and a
# variable set before a command substitution IS visible inside it, so this
# works from within a segment.
_sl_segment_active() {
  case " ${SL_ACTIVE_SEGMENTS-} " in
    *" $1 "*) return 0 ;;
  esac
  # Unset means nobody declared a layout — assume everything is live rather
  # than silently suppressing every critical.
  [ -z "${SL_ACTIVE_SEGMENTS+x}" ]
}

sl_crit_owner() {
  local v context_crit ratelimit_crit
  sl_threshold_default context_crit
  context_crit=$_SL_THRESHOLD_VALUE
  sl_threshold_default ratelimit_crit
  ratelimit_crit=$_SL_THRESHOLD_VALUE
  # The owner must be a segment that is actually rendered. Awarding the slot to
  # an absent segment silently downgrades the one metric the user CAN see: a
  # theme without a context segment, with context critical, would cap a
  # critical rate limit to a watch and show no critical marker anywhere. That
  # is the same fail-silent shape as the threshold mismatch fixed earlier,
  # one layer up.
  if _sl_segment_active context && sl_numeric ctx_pct; then
    v=$(sl_num ctx_pct 0)
    [ "$v" -ge "$context_crit" ] && {
      printf 'context'
      return 0
    }
  fi
  if _sl_segment_active ratelimit && sl_has rl5_pct; then
    v=$(sl_num rl5_pct 0)
    [ "$v" -ge "$ratelimit_crit" ] && {
      printf 'rl5'
      return 0
    }
  fi
  if _sl_segment_active ratelimit && sl_has rl7_pct; then
    v=$(sl_num rl7_pct 0)
    [ "$v" -ge "$ratelimit_crit" ] && {
      printf 'rl7'
      return 0
    }
  fi
  printf ''
}

# sl_state_cap <owner_id> <state>
#
# Downgrades a critical state to watch unless this metric owns the critical
# slot. Segments call it before painting and before asking for a marker, so the
# marker and the colour always agree.
sl_state_cap() {
  local id=$1 state=$2
  if [ "$state" = "crit" ] && [ "$(sl_crit_owner)" != "$id" ]; then
    printf 'watch'
  else
    printf '%s' "$state"
  fi
}

# sl_state_paint <state> <text>
sl_state_paint() {
  local state=$1
  shift
  case "$state" in
    crit)
      sl_code bold
      printf '%s' "$_SL_CODE"
      sl_paint "${SL_THEME_state_crit_color:-red}" "$*"
      [ "${SL_COLOR_ENABLED:-1}" -eq 1 ] && printf '\033[0m'
      return 0
      ;;
    watch) sl_paint "${SL_THEME_state_watch_color:-yellow}" "$*" ;;
    *) printf '%s' "$*" ;;
  esac
}

# sl_state_marker <state>
#
# The redundant, colour-free channel. This is what survives NO_COLOR and
# colour-vision deficiency, and it is the reason the test suite can assert that
# the three states differ in TEXT rather than only in escape sequences.
sl_state_marker() {
  case "$1" in
    crit) printf '%s' "${SL_THEME_state_crit_marker:-!!}" ;;
    watch) printf '%s' "${SL_THEME_state_watch_marker:-!}" ;;
    *) printf '' ;;
  esac
}
