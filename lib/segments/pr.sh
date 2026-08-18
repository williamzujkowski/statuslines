#!/usr/bin/env bash
# pr — the open pull request (or GitLab merge request) for this branch.
#
# Claude Code resolves this itself, so this segment costs no `gh` spawn.
# pr.kind is "mr" for GitLab; review_state may be absent independently of the
# number, so the two are read separately.
segment_pr() {
  local num kind state color label
  sl_has pr_number || return 1
  num=$(sl_get pr_number)
  kind=$(sl_get pr_kind)
  if [ "$kind" = "mr" ]; then label="!"; else label="#"; fi

  color=${SL_THEME_pr_color:-blue}
  state=$(sl_get pr_state)
  case "$state" in
    approved) color=green ;;
    changes_requested) color=red ;;
    pending) color=yellow ;;
    draft) color=dim ;;
  esac

  # The state is spelled out, not encoded only in the color.
  local suffix=""
  case "$state" in
    approved) suffix=" ok" ;;
    changes_requested) suffix=" changes" ;;
    pending) suffix=" review" ;;
    draft) suffix=" draft" ;;
  esac

  sl_paint "$color" "${label}${num}${suffix}"
}
