---
title: "ADR-0001: Themes are parsed, not sourced"
status: accepted
date: "2026-08-17"
---

# ADR-0001: Themes are parsed, not sourced

## Context

Themes need to declare a segment order, a separator, colors, and per-segment
thresholds. The obvious implementation in Bash is to make a theme a shell
snippet and `source` it: it is three lines of code, it is faster than any
parser we could write, and it gives theme authors the full language for free.

The problem is what a theme *is* socially. The whole point of this repository
is that people copy themes from each other — that is what
[statuslin.es](https://statuslin.es/) is, and it is the reason this project
ships themes as separate files at all. If a theme is a shell snippet, then
"install this theme" means "run this stranger's code", on every render, with
the user's full privileges. That is an unreasonable thing to ask of someone who
wanted a different shade of blue.

It also affects us directly: accepting a theme as a pull request would mean
reviewing it as code rather than as data.

## Options considered

1. **Source the theme file.** Trivial, fast, maximally flexible. Makes every
   theme an executable, and makes theme review a code review.
2. **Use an existing format with an existing parser** — TOML, YAML, JSON.
   Correct and declarative, but all three need a parser we do not have. `jq`
   could read JSON, but JSON is a hostile format to hand-edit (no comments) and
   we would be spending our one allowed `jq` call, or adding a second.
3. **A minimal `key = value` parser in pure Bash.** Declarative, comment-
   friendly, no new dependency, and about forty lines.

## Decision

Option 3. A theme is `key = value` lines with `#` comments, parsed by
`sl_theme_parse` in `lib/theme.sh`. Values are trimmed unless quoted.

Two constraints make this safe rather than merely simple:

- **Keys are allowlisted to `[a-z0-9_]+` before use.** The parser assigns with
  `printf -v "SL_THEME_${key}"`, and without the allowlist a theme containing
  `PATH = /evil` or `SL_FIELDS = boom` would clobber shell state. The check is
  the thing that makes the assignment safe; it is not stylistic.
- **Values are only ever data.** No value is ever expanded, evaluated, or used
  to build a command. Theme-supplied names that reach a filesystem path — the
  theme name itself, and segment names — are validated separately in
  `sl_theme_resolve` and `sl_segment_load`.

## Consequences

- Installing a theme cannot execute code. A theme can make the line ugly; it
  cannot read the user's files.
- **"Cannot execute code" was not the same as "cannot do harm", and the first
  version of this decision conflated them.** Theme values are rendered straight
  to the terminal, and the parser did not strip control characters, so a
  `separator` containing `ESC [ 2 J` cleared the user's screen on every render
  — no code execution required, and `NO_COLOR` did not help because the escape
  came from the data rather than from the color layer. The parser now strips
  control characters from every value (`lib/theme.sh`), which is what actually
  makes this consequence true. Anything that renders a theme-supplied string
  inherits that dependency: if a value ever bypasses `sl_theme_parse`, it must
  be scrubbed at its own source.
- Themes can be reviewed as data, which makes accepting community themes a
  reasonable thing to do.
- Theme authors lose conditionals and computation. Anything that needs logic
  has to be a segment, which is the right place for it — segments are code, are
  reviewed as code, and are tested.
- The trimming rule needs quoting for values whose whitespace matters. In
  practice that is `separator`, and getting it wrong silently glues every
  segment together. This is documented in `docs/THEMES.md` and covered by a
  unit test.
- We own a parser, small as it is. It is tested directly in `test/unit.bats`,
  including the key-allowlist case.
