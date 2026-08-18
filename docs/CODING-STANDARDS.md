---
title: "statuslines — Coding Standards"
description: "Change-safety, simplicity, architecture, and accessibility standards for the statuslines repository"
status: canonical
tier: 1
last_updated: "2026-08-17"
related_files: ["../AGENTS.md", "STATUSLINE-CONTRACT.md", "THEMES.md", "adr/"]
load_priority: "always"
review_cycle: "quarterly"
---

# Coding Standards

Adapted from [`docs/CODING_PRACTICES.md`](https://github.com/GSA-TTS/agentic-coding-playbook/blob/main/docs/CODING_PRACTICES.md)
in the GSA-TTS Agentic Coding Playbook. Sections that do not apply to a shell utility with no
network, no database, no auth, and no web UI — API security, database security, CORS, container
images, model evaluation, continuous monitoring — have been dropped. What remains is the part
that makes this codebase safe to change.

`AGENTS.md` is the behavioral contract and takes precedence. This document is the craft detail
behind it. **Key words** follow [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

---

## 1. AI-Generated Code

This project is largely AI-assisted, so the playbook's provenance rules apply directly.

- AI assistance MUST be disclosed at the pull-request level. Per-commit `Co-authored-by:`
  trailers are OPTIONAL.
- A human MUST review every AI-generated change before it merges. Whoever merges owns the code,
  regardless of what wrote it.
- The agent SHOULD explain non-obvious implementation choices in the PR, not just in comments.

Known failure modes to actively check for, because they show up in this codebase specifically:

| Failure mode | What it looks like here |
|---|---|
| Plausible but wrong logic | A percentage computed from a field that is absent, rendering `0%` instead of "unknown" |
| Non-existent APIs | A payload field that was imagined rather than observed. Verify against `docs/STATUSLINE-CONTRACT.md` and a real captured payload |
| Insecure training-data patterns | `echo "$var"`, unquoted expansions, `eval` for indirection, `$(...)` inside a loop |
| Portability blind spots | bash 4+ syntax that works on the author's Linux box and breaks on stock macOS bash 3.2 |

Mitigation is not "be careful": it is a fixture, a golden file, and a `make check` run whose
output appears in the PR.

---

## 2. Input Validation and Output Encoding

The status line has exactly one trust boundary: **the JSON payload arriving on stdin.**
Everything in it — directory paths, git branch names, model names, agent names — is
attacker-influenceable, because a repository someone else authored can name a branch whatever
it likes.

The agent MUST:

- Validate at the boundary, once, in `lib/core.sh`. Downstream segments consume already-scrubbed
  values and MUST NOT re-parse raw JSON.
- Use an allowlist for anything that selects behavior. A theme name, a segment name, or a color
  token from user config MUST be checked against the known set, never used to build a path or a
  variable name unchecked.
- Strip C0 control characters and DEL from every payload-derived string before it can reach
  stdout. An unstripped `ESC` in a branch name is a terminal-injection vector: it can repaint
  the user's screen, hide text, or forge output above the prompt.
- Bound length before rendering. An unbounded path in an 80-column terminal destroys the layout.
- Encode for the output context, which here means: emit ANSI SGR only, and never let payload
  data supply the escape itself.

The agent MUST NOT:

- Use `eval`, or `printf "$value"` with a payload value in the format position.
- Interpolate a payload value into a command string, a filename, or a variable name.
- Assume a numeric-looking field is numeric. Use `sl_int` / `sl_num`, which fall back safely.

> Related: `AGENTS.md` §4.1, §5.2.

---

## 3. Secrets

There are no secrets in this repository and there MUST NOT be. The realistic risk is the
opposite direction: **leaking the maintainer's environment into a public repo through test
fixtures.**

The agent MUST:

- Scrub every captured fixture before committing it — replace real home directories with
  `/home/user` or `/Users/user`, real session UUIDs with a fixed dummy, real project names with
  neutral ones, and remove `transcript_path` values that reveal a directory layout.
- Never commit a raw payload captured from a live session without that scrub.
- Treat the repository's own git history as public and permanent. A scrub after the fact is not
  a fix; it requires a history rewrite and a force-push, which is a §3.2 approval action.

If a secret or personal path is committed, the agent MUST stop and report it rather than
quietly amending — the human decides whether to rewrite history.

---

## 4. Error Handling

The playbook requires explicit error signaling and no silent fallbacks. A status line
complicates that, because it must never crash the user's prompt. The reconciliation is
**degrade visibly**:

- Every error MUST be handled explicitly. No bare `|| true` that discards a failure whose cause
  matters, and no empty error branch.
- The distinction that matters is *recoverable* vs *fatal-to-a-segment*. A git command timing
  out is recoverable: the git segment renders empty, the rest of the line renders. An
  unparseable payload is fatal to the whole render: it produces a minimal line plus a visible
  degraded marker, never a blank line and never a traceback.
- A value that could not be computed MUST render as unknown, not as zero. `sl_has` exists for
  exactly this, and using `sl_get field 0` where the field is genuinely absent is the bug this
  standard is written to prevent.
- Error text MUST NOT leak internal detail into the user's prompt. `statusline error` is
  acceptable output; a shell trace is not. Detail goes to stderr, and to `STATUSLINE_DEBUG=1`.
- The script MUST exit 0 when degraded. A non-zero exit means "this was not a status line
  invocation".

There is no logging subsystem here and there MUST NOT be one — a status line that writes logs on
every render is a disk-filling bug. `STATUSLINE_DEBUG=1` writing to stderr is the whole
debugging story.

---

## 5. Change Safety and Verification

### 5.1 Test-First

- A defect MUST get its regression fixture **before** the fix. The fixture MUST fail against the
  broken code — if it passes before the fix, it does not test the bug.
- Name regression fixtures after their issue: `test/fixtures/issue-42-branch-with-escape.json`.
- New behavior MUST NOT merge without a test. `make check` passing is the merge gate.

### 5.2 Golden Tests Are The Primary Mechanism

Rendering is a deterministic function from payload plus theme to a string, which makes golden
tests the natural fit and the reason `test/golden/` exists.

- Every (fixture, theme) pair that matters MUST have a golden file.
- Golden files MUST be regenerated **explicitly** via `make golden`, and the diff MUST be
  reviewed in the PR. Auto-accepting a golden diff defeats the entire mechanism.
- A PR that regenerates goldens MUST say, in words, why the new output is correct.

### 5.3 Determinism

Render output MUST be a pure function of the payload, the theme, and declared environment
(`NO_COLOR`, `COLUMNS`, `STATUSLINE_THEME`). Specifically:

- No wall-clock reads in rendering logic. Durations come from the payload's `duration_ms`, not
  from `date`. A segment that genuinely needs the current time MUST accept it as an injectable
  parameter so tests can pin it.
- No dependence on the current working directory of the test runner.
- No dependence on the developer's real git repository — git-dependent tests MUST build a
  scratch repo in a temp dir with pinned author, date, and branch.

Non-deterministic output is untestable output, and untestable output is where this project's
bugs will live.

### 5.4 Property-Based Thinking

Full property-based testing tooling is overkill for a shell project, but the parser MUST hold
these invariants, and they SHOULD be exercised with a fuzz-ish fixture sweep:

1. For any input at all — valid JSON, invalid JSON, empty, binary — the script exits 0 and
   prints at most the configured number of lines.
2. No output ever contains a raw `ESC` byte that did not originate from the theme's own color
   tokens.
3. Rendering the same payload twice produces byte-identical output.
4. Removing any single field from a valid payload never crashes the render.

Invariant 4 is cheaply checkable by generating the payload variants programmatically; that
sweep SHOULD live in the test suite.

---

## 6. Scope, Simplicity, Maintainability

### 6.1 The Laziness Ladder

Before writing code, stop at the **first rung that holds**:

1. Does this need to exist at all? If not, skip it.
2. Does a bash builtin or parameter expansion already do it? Use it.
3. Does `jq` already do it, inside the one call we are already making? Use it.
4. Does an existing helper in `lib/` solve it? Use it.
5. Can it be one line? Make it one line.
6. Only then: write the minimum code that works.

This ladder is load-bearing here because every rung skipped is a process spawn, and process
spawns are the latency budget.

> **Lazy is not negligent.** Never simplify away: payload validation (§2), the degradation path
> (§4), control-character stripping, or the no-color path. Non-trivial logic leaves a test
> behind.

Mark an intentional shortcut with a comment naming it and its ceiling — "linear scan, fine
under ~20 segments, revisit if themes grow" — so "later" does not become "never".

### 6.2 YAGNI, Specifically For This Project

A status line accretes knobs. The rule: **a configuration option MUST NOT ship without a theme
that uses it.** If no shipped theme exercises the option, it is speculative, untested surface
area, and it does not ship.

### 6.3 DRY and the Rule of Three

Extract at the third occurrence, not the second. Two similar segments are a coincidence; five
segments formatting a colored percentage is a helper.

### 6.4 Size and Complexity

| Unit | Limit |
|---|---|
| Function | ≤ 50 lines of logic |
| File | ≤ 400 lines (a cohesive 400–600 is acceptable with justification) |
| Function parameters | ≤ 5 |
| Nesting depth | ≤ 3 |
| Process spawns per render | ≤ 4 (see `AGENTS.md` §4.4) |

Exceeding a limit requires written justification in the PR. "It's complex because…" is the
required form; silence is not.

### 6.5 Module Boundaries

The module contract in this repository is small and MUST be respected:

- `lib/core.sh` owns parsing. It is the only file that runs `jq` against the payload.
- `lib/render.sh` owns layout, separators, truncation, and dispatch. It is the only file that
  decides what goes where.
- `lib/segments/<name>.sh` exports exactly one function, `segment_<name>`, which writes its
  fragment to stdout and signals its outcome through its exit status. A segment MUST NOT
  know about separators, about other segments, or about the terminal width.
The segment exit status is a three-way signal, not a boolean:

| Status | Meaning | Rendered as |
|---|---|---|
| `0` | wrote a fragment | the fragment |
| `1` | nothing to show — a field was absent, which is normal | nothing |
| `>1` | the segment failed | a visible marker |

The third row is the one that is easy to get wrong. A segment that crashes and a segment that has
nothing to say are both absent from the line, and if they render identically then a broken segment
is invisible — degraded state presented as healthy, which §4 forbids. Failure to *load* a segment
at all (a missing file, a syntax error, a file that does not define the function it promised) is
treated the same way.

- `lib/colors.sh` owns every escape sequence. No other file may contain a literal `\033`.

A segment reaching around the renderer to emit a separator, or a renderer special-casing one
segment by name, is a boundary violation and MUST be flagged in review.

---

## 7. Architecture Discipline

### 7.1 ADRs

Write an ADR in `docs/adr/` for the triggers in `AGENTS.md` §10.1. Format: context, options,
decision, consequences. One page. `docs/adr/0001-theme-config-format.md` is the reference for
length and tone.

### 7.2 Design by Contract

Each `lib/` function MUST document, in a comment above it: what it consumes, what it emits, and
what it does on failure. The segment contract in §6.5 is the most important one — it is what
lets a contributor add a segment without reading the renderer.

### 7.3 Separation of Concerns

Parsing, formatting, and coloring are three separate concerns and MUST stay in three separate
places. The recurring temptation is a segment that reads the payload directly and emits its own
color codes because it is "just one line". That is how the previous version became untestable.

---

## 8. Accessibility

The playbook's Section 508 / WCAG guidance is written for web UI. Two of its rules translate
directly to a terminal status line, and they are not optional:

- **Color MUST NOT be the sole carrier of meaning.** A context gauge that is red at 90% MUST
  also print the number. A health indicator that is a colored dot MUST have a distinguishable
  glyph or label, because a red dot and a green dot are the same dot to a colorblind user and to
  a monochrome terminal. Every shipped theme MUST remain fully readable with color stripped —
  which is exactly what the `plain` theme tests.
- **Contrast is not ours to control, so do not assume it.** The terminal's background is unknown
  and user-themed. Themes MUST use the 16 standard SGR colors, which the user's own terminal
  theme maps to readable values, rather than hardcoded 256-color or truecolor values that may
  land invisibly close to their background. A theme that requires truecolor MUST declare it.

Additional terminal-specific requirements:

- `NO_COLOR` MUST be honored ([no-color.org](https://no-color.org/)).
- Screen readers reading a terminal do not benefit from box-drawing glyphs. The default theme
  MUST NOT depend on Nerd Font or powerline glyphs; themes that do MUST declare
  `requires_font` and be documented as such in `docs/THEMES.md`.
- Width MUST be computed in display columns, not bytes. A CJK path or a wide glyph is two
  columns, and truncating by byte count cuts multibyte characters in half and corrupts the line.

---

## 9. Version Control and Release Management

This project follows the playbook's release guidance. `AGENTS.md` §10.6 is the binding version;
the mechanics live here.

- **SemVer 2.0.0.** The bump table is in `AGENTS.md` §10.6.
- **Conventional Commits 1.0.0** for all commits.
- **CI validation of commit format** is done with a pinned PR-title-lint action rather than a
  local `commitlint` install, per the playbook's recommendation — it avoids an npm dependency
  and its supply-chain surface.
- **Squash-merge is the required merge strategy.** The validated PR title becomes the squashed
  commit subject that release-please reads for the version bump. This also gives the linear
  history release automation wants. A merge commit carrying unvalidated commit subjects will
  produce a wrong changelog.
- `commitlint` locally is OPTIONAL convenience. `make setup` instead installs a dependency-free
  bash `commit-msg` hook that checks the same shape.
- **CHANGELOG.md follows Keep a Changelog** and is generated by release-please from commits. It
  MUST NOT be hand-edited.
- **Release tags** are `v<version>`, created by release-please. Tags for releases SHOULD be
  signed; commits SHOULD be signed where the maintainer has signing configured.
- **Branch protection** on `main`: require a PR, require CI status checks, require linear
  history.
- **Traceability:** every release traces to commits via its tag, and every user-facing change
  appears in the changelog with its version and date.

---

## Attribution

Adapted from `docs/CODING_PRACTICES.md` in
[GSA-TTS/agentic-coding-playbook](https://github.com/GSA-TTS/agentic-coding-playbook).
The Laziness Ladder in §6.1 originates there, itself inspired by the MIT-licensed
[ponytail](https://github.com/DietrichGebert/ponytail) ruleset.
