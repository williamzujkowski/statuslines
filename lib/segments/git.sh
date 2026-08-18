#!/usr/bin/env bash
# git — the current branch, read without invoking git.
#
# Reading .git/HEAD directly costs one file read; `git rev-parse` costs a
# process spawn, which is about a quarter of the per-segment budget
# (AGENTS.md §4.4). git is also forbidden from being spawned on the render
# path at all when it might take a lock (§3.3), and this avoids the question.
#
# Falls back to the payload's own worktree fields when the directory cannot be
# resolved, since Claude Code already knows them.
_sl_git_dir() {
  local dir=$1 gitpath
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ]; then
      printf '%s' "$dir/.git"
      return 0
    fi
    if [ -f "$dir/.git" ]; then
      # A linked worktree: `.git` is a file containing `gitdir: <path>`.
      IFS= read -r gitpath <"$dir/.git" || return 1
      gitpath=${gitpath#gitdir:}
      gitpath=${gitpath# }
      # A `.git` file is attacker-controlled content in a cloned repository.
      gitpath=${gitpath//[[:cntrl:]]/}
      [ -n "$gitpath" ] || return 1
      case "$gitpath" in
        /*) printf '%s' "$gitpath" ;;
        *) printf '%s' "$dir/$gitpath" ;;
      esac
      return 0
    fi
    dir=${dir%/*}
  done
  return 1
}

segment_git() {
  local cwd gitdir head branch="" marker="" color

  branch=$(sl_get wt_branch)
  if [ -z "$branch" ]; then
    cwd=$(sl_get cwd)
    [ -n "$cwd" ] || return 1
    gitdir=$(_sl_git_dir "$cwd") || return 1
    [ -r "$gitdir/HEAD" ] || return 1
    IFS= read -r head <"$gitdir/HEAD" || return 1
    case "$head" in
      "ref: refs/heads/"*)
        branch=${head#ref: refs/heads/}
        ;;
      "ref: "*)
        branch=${head#ref: }
        ;;
      *)
        # Detached HEAD: show the short object name, marked as detached so it
        # is not mistaken for a branch.
        branch="@${head:0:7}"
        ;;
    esac
  fi

  # Scrub here, not at the call site: this value came off the filesystem and
  # so never passed through the jq sanitizer in lib/core.sh. Without this a
  # branch named with ANSI escapes repaints the user's terminal on every render.
  branch=$(sl_scrub "$branch" "${SL_THEME_git_max_length:-40}")
  [ -n "$branch" ] || return 1

  # A worktree marker, from whichever field the payload provided. This is a
  # glyph-free marker so it survives the default theme's no-Nerd-Font rule.
  if sl_has git_worktree || sl_has wt_name; then
    marker=${SL_THEME_git_worktree_marker:-+wt}
  fi

  color=${SL_THEME_git_color:-green}
  sl_paint "$color" "${branch}${marker:+ $marker}"
}
