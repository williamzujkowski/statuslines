---
title: "ADR-0002: Read .git/HEAD directly instead of invoking git"
status: accepted
date: "2026-08-17"
---

# ADR-0002: Read `.git/HEAD` directly instead of invoking git

## Context

Showing the branch is the single most-wanted segment, and the obvious
implementation is `git rev-parse --abbrev-ref HEAD`. The previous version of
this status line did exactly that, on every render.

Two things make that a poor fit here.

**Latency.** Claude Code debounces status line invocations by 300 ms and
*aborts* an in-flight run when a new trigger arrives. A slow render does not
render late; it does not render at all. A `git` spawn is roughly a millisecond
of process creation plus repository discovery, and it is the difference between
one spawn per render and two.

**Locking.** Renders happen constantly, including while the user is mid-edit
and while other tooling is touching the repository. Several git subcommands
take `index.lock`, and a status line that contends for it can stall the
terminal on someone else's operation.

## Decision

Read `.git/HEAD` from the filesystem and parse it in Bash.

`_sl_git_dir` walks up from the working directory looking for `.git`. When
`.git` is a directory, `HEAD` is inside it. When `.git` is a *file* — a linked
worktree — it contains `gitdir: <path>`, which is followed. `HEAD` then holds
either `ref: refs/heads/<branch>` or a raw object name for a detached HEAD.

Where Claude Code already knows the answer, its own fields are preferred:
`worktree.branch` from a `--worktree` session, and `workspace.git_worktree` for
the worktree marker.

## Consequences

- Zero process spawns for the branch. Total spawns per render is one, for `jq`.
- No possibility of lock contention, and no possibility of this project causing
  a write to a user's repository.
- **Values read this way bypass the payload sanitizer.** This is the real cost,
  and we shipped the bug before we caught it: everything from the payload is
  scrubbed of control characters by the `jq` program in `lib/core.sh`, but
  `.git/HEAD` is read directly, so a branch named with ANSI escapes reached
  stdout and could repaint the terminal of anyone who opened the repository.
  Filesystem-derived values are now scrubbed at their source with `sl_scrub`,
  and there is a regression test in `test/invariants.bats`. Any future segment
  that reads from disk inherits this obligation.
- We reimplement a small amount of git. Specifically: `.git` files, and
  detached HEAD. We do not attempt packed refs, `HEAD` pointing at a non-branch
  ref beyond showing it verbatim, or anything requiring the object database.
- Dirty state, ahead/behind counts, and stash counts are *not* available this
  way — they genuinely need `git status`, which is both a spawn and a lock
  risk. They are deliberately not shipped; if they are added it will be behind
  an explicit opt-in with a cache, and it will need its own ADR.
