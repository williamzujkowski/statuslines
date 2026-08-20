#!/usr/bin/env bash
#
# statuslines — a themeable status line for Claude Code.
# https://github.com/williamzujkowski/statuslines
#
# x-release-please-start-version
# version: 0.2.1
# x-release-please-end
#
# Install by pointing Claude Code at this file:
#
#   "statusLine": {
#     "type": "command",
#     "command": "bash ~/path/to/statuslines/statusline.sh",
#     "padding": 0
#   }
#
# Select a theme with STATUSLINE_THEME, or by writing one line to
# ~/.config/statuslines/config:  theme = dashboard
#
# Requires: bash 3.2+, jq. git is read from the filesystem, never invoked.

set -uo pipefail

# `set -e` is deliberately absent.
#
# This script's whole job is to always produce a line. Under `set -e` any
# unguarded non-zero return — and segments return non-zero routinely, to mean
# "I have nothing to show" — would abort the render and leave the user with a
# blank status line and no explanation. Errors are instead handled explicitly
# at each call site (AGENTS.md §4.5, docs/CODING-STANDARDS.md §4).

# ── Resolve our own directory, following one level of symlink ─────────────
# Users symlink this file into ~/.claude/, so $0 is not necessarily where the
# library lives.
SL_SELF=${BASH_SOURCE[0]}
if [ -L "$SL_SELF" ]; then
  SL_LINK=$(readlink "$SL_SELF" 2>/dev/null) || SL_LINK=""
  if [ -n "$SL_LINK" ]; then
    case "$SL_LINK" in
      /*) SL_SELF=$SL_LINK ;;
      *) SL_SELF="${SL_SELF%/*}/$SL_LINK" ;;
    esac
  fi
fi
SL_ROOT=${SL_SELF%/*}
[ "$SL_ROOT" = "$SL_SELF" ] && SL_ROOT=.
export SL_ROOT

# ── Load the library ─────────────────────────────────────────────────────
# A bundled single-file build inlines these; see scripts/bundle.sh.
if [ -z "${SL_BUNDLED:-}" ]; then
  for _sl_lib in core colors theme render; do
    # shellcheck source=/dev/null # path is computed at runtime from SL_ROOT
    if ! . "${SL_ROOT}/lib/${_sl_lib}.sh" 2>/dev/null; then
      printf 'statusline: cannot load lib/%s.sh from %s\n' "$_sl_lib" "$SL_ROOT" >&2
      # Emit something rather than nothing: a blank line reads as "the status
      # line is off", which sends the user looking in the wrong place.
      printf 'statusline: broken install'
      exit 0
    fi
  done
fi

# ── Read the payload ─────────────────────────────────────────────────────
# Claude Code aborts an in-flight run when a new trigger arrives (300 ms
# debounce), so there is no benefit to waiting on a stalled stdin.
SL_INPUT=$(cat 2>/dev/null) || SL_INPUT=""

# ── Configure ────────────────────────────────────────────────────────────
sl_colors_init

SL_THEME_NAME=${STATUSLINE_THEME:-}
if [ -z "$SL_THEME_NAME" ]; then
  for _sl_cfg in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/statuslines/config" \
    "$HOME/.claude/statuslines.conf"; do
    if [ -r "$_sl_cfg" ]; then
      sl_theme_load "$_sl_cfg"
      SL_THEME_NAME=$(sl_theme_get theme '')
      break
    fi
  done
fi
[ -n "$SL_THEME_NAME" ] || SL_THEME_NAME=default

if SL_THEME_PATH=$(sl_theme_resolve "$SL_THEME_NAME"); then
  sl_theme_load "$SL_THEME_PATH"
else
  # An unknown theme name is a configuration error the user needs to see, but
  # not a reason to show nothing — fall back and say so.
  if SL_THEME_PATH=$(sl_theme_resolve default); then
    sl_theme_load "$SL_THEME_PATH"
  fi
  printf 'statusline: unknown theme %s, using default\n' "$SL_THEME_NAME" >&2
fi

# A theme may switch color off wholesale. Per-key `none` cannot do this on its
# own, because segments choose some of their own colors — threshold ramps and
# dim labels are decided in code, not in the theme — so a theme that wants a
# genuinely colorless line needs a global switch. An explicit STATUSLINE_COLOR
# or NO_COLOR from the environment still wins over the theme.
# shellcheck disable=SC2034 # SL_COLOR_ENABLED is read by sl_paint in lib/colors.sh
if [ -z "${STATUSLINE_COLOR-}" ] && [ -z "${NO_COLOR-}" ]; then
  case "$(sl_theme_get color '')" in
    off | none | 0) SL_COLOR_ENABLED=0 ;;
    on | always | 1) SL_COLOR_ENABLED=1 ;;
  esac
fi

# ── Parse and render ─────────────────────────────────────────────────────
sl_parse "$SL_INPUT"
sl_render

# Always succeed. A non-zero exit here would be reported by `claude --debug` as
# a failing status line even when the line rendered correctly.
exit 0
