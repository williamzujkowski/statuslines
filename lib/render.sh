#!/usr/bin/env bash
# render.sh — segment dispatch, separators, and width fitting.
#
# The only file that decides what goes where. Segments do not know about
# separators, about each other, or about the terminal width; that ignorance is
# what lets a contributor add a segment without reading this file
# (CODING-STANDARDS §6.5).

# sl_segment_load <name>
# Sources a segment file once. Returns non-zero if there is no such segment.
#
# The name reaches a filesystem path, so it is validated first — a theme is
# just a text file and `../../etc/passwd` is a legal-looking segment name.
sl_segment_load() {
  local name=$1
  case "$name" in
    "" | *[!a-z0-9_]*) return 1 ;;
  esac

  if declare -f "segment_${name}" >/dev/null 2>&1; then
    return 0
  fi

  [ -r "${SL_ROOT}/lib/segments/${name}.sh" ] || return 1
  # shellcheck source=/dev/null
  . "${SL_ROOT}/lib/segments/${name}.sh" || return 1

  declare -f "segment_${name}" >/dev/null 2>&1
}

# sl_segment_render <name>
# Emits the segment's fragment, or nothing.
#
# A failing segment is contained to its own slot: it must not be able to abort
# the render (AGENTS.md §4.5). This is the one place `|| true` is correct, and
# the reason is that the alternative is a blank status line.
sl_segment_render() {
  local name=$1 out=""
  sl_segment_load "$name" || return 1
  out=$("segment_${name}" 2>/dev/null) || out=""
  [ -n "$out" ] || return 1
  printf '%s' "$out"
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
  local sep sep_colored name frag line width columns
  local -a drop_order=()

  sep=${SL_THEME_separator:- | }
  sep_colored=$(sl_paint "${SL_THEME_separator_color:-dim}" "$sep")

  for name in "${names[@]}"; do
    if frag=$(sl_segment_render "$name"); then
      frags+=("$frag")
    else
      frags+=("")
    fi
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
