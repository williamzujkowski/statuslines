#!/usr/bin/env bash
# dir — the working directory.
#
# Renders the basename by default because the full path is the single biggest
# consumer of an 80-column line. `dir_style = full|basename|short` selects.
# `short` keeps the last N components (dir_depth, default 2).
segment_dir() {
  local path style depth out
  sl_has cwd || return 1
  path=$(sl_get cwd)
  style=${SL_THEME_dir_style:-basename}
  depth=${SL_THEME_dir_depth:-2}
  case "$depth" in *[!0-9]* | '') depth=2 ;; esac

  case "$style" in
    full)
      out=$path
      ;;
    short)
      local rest=$path acc="" i=0 part
      while [ "$i" -lt "$depth" ] && [ -n "$rest" ] && [ "$rest" != "/" ]; do
        part=${rest##*/}
        rest=${rest%/*}
        [ -n "$part" ] || {
          rest=${rest%/*}
          continue
        }
        if [ -n "$acc" ]; then acc="${part}/${acc}"; else acc=$part; fi
        i=$((i + 1))
      done
      out=$acc
      [ "$rest" != "" ] && [ "$rest" != "/" ] && out=".../${out}"
      ;;
    *)
      out=${path##*/}
      [ -n "$out" ] || out=$path
      ;;
  esac

  # Home is the one substitution worth making unconditionally: it is both
  # shorter and less revealing in a screenshot.
  case "$out" in
    "$HOME"*) out="~${out#"$HOME"}" ;;
  esac

  sl_paint "${SL_THEME_dir_color:-blue}" "$out"
}
