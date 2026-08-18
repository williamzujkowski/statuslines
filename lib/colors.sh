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
    printf '%s' "$good"
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
