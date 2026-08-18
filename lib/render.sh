#!/usr/bin/env bash
# render.sh — segment dispatch, separators, and width fitting.
#
# The only file that decides what goes where. Segments do not know about
# separators, about each other, or about the terminal width; that ignorance is
# what lets a contributor add a segment without reading this file
# (CODING-STANDARDS §6.5).

# Segment outcome, set by sl_segment_render on every call:
#   ok      — produced a fragment
#   empty   — ran fine and had nothing to show (a field was absent)
#   missing — the theme names a segment that does not exist
#   broken  — the segment exists but failed to load or errored
#
# `empty` renders nothing. `missing` and `broken` render a visible marker,
# because a segment that is silently absent because it crashed looks exactly
# like one that is silently absent because it had nothing to say, and
# AGENTS.md §7.3 forbids presenting degraded state as healthy.
SL_SEGMENT_STATUS=empty

# sl_segment_load <name>
# Sources a segment file once. Sets SL_SEGMENT_STATUS on failure.
#
# The name reaches a filesystem path, so it is validated first — a theme is
# just a text file and `../../etc/passwd` is a legal-looking segment name.
sl_segment_load() {
  local name=$1
  case "$name" in
    "" | *[!a-z0-9_]*)
      SL_SEGMENT_STATUS=missing
      return 1
      ;;
  esac

  if declare -f "segment_${name}" >/dev/null 2>&1; then
    return 0
  fi

  if [ ! -r "${SL_ROOT}/lib/segments/${name}.sh" ]; then
    SL_SEGMENT_STATUS=missing
    return 1
  fi

  # A syntax error in a segment file surfaces here, at source time, not when
  # the function is called. This is the branch that catches a half-saved edit.
  # shellcheck source=/dev/null
  if ! . "${SL_ROOT}/lib/segments/${name}.sh" 2>/dev/null; then
    SL_SEGMENT_STATUS=broken
    return 1
  fi

  if ! declare -f "segment_${name}" >/dev/null 2>&1; then
    # The file loaded but does not define what it promised.
    SL_SEGMENT_STATUS=broken
    return 1
  fi

  return 0
}

# sl_segment_render <name>
# Sets SL_FRAG to the segment's fragment and SL_SEGMENT_STATUS to the outcome.
#
# It assigns rather than prints because the caller needs BOTH values, and
# wrapping this in `$( )` to collect the fragment would run it in a subshell
# and discard the status. Segments themselves still write to stdout; only this
# internal boundary uses a variable. As a side effect it removes one fork per
# segment, which is the cheap half of #8.
#
# A failing segment is contained to its own slot: it must never abort the
# render (AGENTS.md §4.5). Containment is not the same as concealment, so the
# failure is still reported through SL_SEGMENT_STATUS.
#
# Return convention for segment authors:
#   return 0  — wrote a fragment
#   return 1  — nothing to show; this is normal and renders as empty
#   return >1 — something went wrong; renders as a visible marker
sl_segment_render() {
  local name=$1 out="" rc=0
  SL_SEGMENT_STATUS=empty
  SL_FRAG=""

  sl_segment_load "$name" || return 1

  # stderr is discarded because Claude Code hides it anyway, so letting it
  # through would corrupt nothing but would also help nobody. Under
  # STATUSLINE_DEBUG it is passed to the real stderr, where `claude --debug`
  # will show it.
  if [ -n "${STATUSLINE_DEBUG-}" ]; then
    out=$("segment_${name}")
    rc=$?
  else
    out=$("segment_${name}" 2>/dev/null)
    rc=$?
  fi

  if [ "$rc" -gt 1 ]; then
    SL_SEGMENT_STATUS=broken
    return 1
  fi

  if [ -z "$out" ]; then
    SL_SEGMENT_STATUS=empty
    return 1
  fi

  SL_SEGMENT_STATUS=ok
  SL_FRAG=$out
  return 0
}

# sl_join <separator> <fragment>...
sl_join() {
  local sep=$1 out="" first=1
  shift
  local part
  for part in "$@"; do
    [ -n "$part" ] || continue
    if [ "$first" -eq 1 ]; then
      out=$part
      first=0
    else
      out="${out}${sep}${part}"
    fi
  done
  printf '%s' "$out"
}

# sl_render_line <segment names...>
#
# Renders one line, then fits it to the terminal width by dropping segments.
#
# Claude Code exports COLUMNS (v2.1.153+). `tput cols` does not work here
# because stdout is a pipe, so COLUMNS is the only width signal available;
# when it is missing, fitting is skipped rather than guessed at.
sl_render_line() {
  local -a names=("$@")
  local -a frags=()
  local sep sep_colored name line width columns
  local -a drop_order=()

  sep=${SL_THEME_separator:- | }
  sep_colored=$(sl_paint "${SL_THEME_separator_color:-dim}" "$sep")

  local marker
  marker=${SL_THEME_error_marker:-?}
  for name in "${names[@]}"; do
    # No command substitution here: sl_segment_render assigns SL_FRAG and
    # SL_SEGMENT_STATUS, and a subshell would discard both.
    sl_segment_render "$name" || :
    case "$SL_SEGMENT_STATUS" in
      ok) frags+=("$SL_FRAG") ;;
      broken | missing)
        # sl_scrub as well as the parser-level scrub in lib/theme.sh: this is
        # the one place a theme-supplied *name* reaches the terminal, and it
        # also bounds the length so an absurd name cannot blow out the line.
        frags+=("$(sl_paint "${SL_THEME_error_color:-red}" "${marker}$(sl_scrub "$name" 24)")")
        ;;
      *) frags+=("") ;;
    esac
  done

  line=$(sl_join "$sep_colored" "${frags[@]}")

  columns=${COLUMNS:-0}
  case "$columns" in
    "" | *[!0-9]*) columns=0 ;;
  esac
  # Claude Code renders its own auto-compact notice alongside the status line,
  # so the full terminal width is not actually ours to fill.
  local reserve
  reserve=${SL_THEME_width_reserve:-0}
  case "$reserve" in *[!0-9]*) reserve=0 ;; esac
  if [ "$columns" -gt "$reserve" ]; then
    columns=$((columns - reserve))
  fi

  if [ "$columns" -le 0 ]; then
    printf '%s' "$line"
    return 0
  fi

  width=$(sl_width "$line")
  [ "$width" -le "$columns" ] && {
    printf '%s' "$line"
    return 0
  }

  # Over budget. Drop segments in the theme's declared order, falling back to
  # right-to-left, and keep dropping until it fits or only the first survives.
  # Dropping beats truncating because a half-cut segment reads as corruption
  # while a missing one reads as a missing segment.
  local spec_drop
  spec_drop=${SL_THEME_drop_order:-}
  if [ -n "$spec_drop" ]; then
    # shellcheck disable=SC2206 # deliberate word splitting: drop_order is a
    # whitespace-separated segment list, and every name is validated in
    # sl_segment_load before it is used for anything.
    drop_order=($spec_drop)
  else
    # Default: right to left, so the rightmost segment is the first to go.
    local i
    for i in $(sl_seq 0 $((${#names[@]} - 1))); do
      drop_order+=("${names[$((${#names[@]} - 1 - i))]}")
    done
  fi

  local victim idx
  for victim in "${drop_order[@]}"; do
    # Never drop the last surviving segment: an empty line is worse than a
    # cramped one.
    local remaining=0
    for idx in $(sl_seq 0 $((${#frags[@]} - 1))); do
      [ -n "${frags[$idx]}" ] && remaining=$((remaining + 1))
    done
    [ "$remaining" -le 1 ] && break

    for idx in $(sl_seq 0 $((${#names[@]} - 1))); do
      if [ "${names[$idx]}" = "$victim" ]; then
        frags[idx]=""
      fi
    done

    line=$(sl_join "$sep_colored" "${frags[@]}")
    width=$(sl_width "$line")
    [ "$width" -le "$columns" ] && break
  done

  printf '%s' "$line"
}

# sl_render
# Renders every line the theme declares.
#
# When parsing failed there is nothing to render from, so this emits a single
# visibly degraded line instead. Silence would look like a configuration
# problem; a wrong-but-plausible line would be worse still (AGENTS.md §7.3).
sl_render() {
  local n=1 spec out first=1

  if [ "${SL_DEGRADED:-0}" -eq 1 ]; then
    printf '%s' "$(sl_paint red "statusline degraded")"
    printf '%s' "$(sl_paint dim ": ${SL_DEGRADED_REASON:-unknown}")"
    return 0
  fi

  while [ "$n" -le 9 ]; do
    spec=$(sl_theme_get "line${n}" '')
    n=$((n + 1))
    [ -n "$spec" ] || continue

    # shellcheck disable=SC2086 # deliberate word splitting: the spec is a
    # whitespace-separated segment list, and each name is validated in
    # sl_segment_load before it is used for anything.
    out=$(sl_render_line $spec)
    [ -n "$out" ] || continue

    [ "$first" -eq 1 ] || printf '\n'
    printf '%s' "$out"
    first=0
  done
}
