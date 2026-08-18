---
title: "statuslines — Theme Reference"
description: "The theme file format, resolution order, the complete segment and theme-key reference, the color vocabulary, accessibility rules, and width fitting"
status: canonical
tier: 1
last_updated: "2026-08-17"
related_files: ["../AGENTS.md", "CODING-STANDARDS.md", "STATUSLINE-CONTRACT.md", "../lib/render.sh", "../lib/theme.sh", "../lib/segments/", "../themes/"]
load_priority: "always"
review_cycle: "quarterly"
---

# Theme Reference

A theme decides which segments appear, in what order, on how many lines, in what colors, and what
gets dropped when the terminal is too narrow. It is a text file. It is never executed.

This document is the reference for that file: the format, every segment, every key the engine
actually reads, and the rules a theme has to satisfy to ship. `AGENTS.md` §4.2 and §4.3 are the
binding rules for output and glyphs; `docs/CODING-STANDARDS.md` §8 is binding for accessibility.
Where this document disagrees with either, they win and this file is the bug.

**Key words** — "MUST", "MUST NOT", "SHOULD", "MAY" — follow
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

---

## 1. File format

`key = value`, one per line. `#` starts a comment and runs to end of line. Blank lines are
ignored. Lines without an `=` are ignored. Whitespace around the key and around the `=` is
insignificant.

```
# themes/minimal.conf
name        = minimal
description = Directory, branch, context, cost
requires    = none

line1 = dir git context cost

separator       = " · "
separator_color = dim
```

### 1.1 Values are trimmed unless quoted

This is the one rule that catches everyone.

Leading and trailing whitespace is stripped from every value. To keep it, wrap the value in double
or single quotes; the outer pair is removed and everything between it is preserved verbatim.

```
separator = " | "     # renders:  dir | git | model
separator = |         # renders:  dir|git|model
```

The trimming exists because almost every other value — a color name, a threshold, a segment list —
is cleaner without it, and a config file where `dir_color = blue ` fails because of a trailing
space is a bad config file. The quoting exists because `separator` is the one value that is
essentially always padded, and unquoted trimming there does not produce an error. It produces a
line that renders, looks subtly wrong, and sends the user reading `lib/render.sh` for a bug that is
in their config.

In practice: quote `separator`. Quote anything else whose spaces are load-bearing. Leave the rest
bare.

### 1.2 Themes are parsed, never sourced

Sourcing a theme would be shorter and faster. It is not done, because a theme is a file people copy
from the internet, and sourcing one would make "install this theme" mean "run this code". Parsing
is what keeps a theme declarative — and what makes a theme safe to accept as a pull request.

Two consequences worth knowing:

- Shell syntax in a theme file does nothing. No command substitution, no expansions, no
  conditionals. A value is a literal string.
- Keys are allowlisted to `[a-z0-9_]+` and may not begin with a digit or underscore, because the
  key is used to name a shell variable via `printf -v`. Without that check, a key of `PATH` — or
  `SL_FIELDS[0]` — would clobber shell state from a text file. A key that fails the allowlist is
  skipped silently.

### 1.3 An empty value means "use the default"

`sl_theme_get` falls back to the built-in default when a key is unset *or* set to the empty string.
`dir_color =` is therefore the same as omitting `dir_color`, not a way to turn color off for that
segment. Use `dir_color = none` for that.

---

## 2. Resolution and search order

### 2.1 Which theme

First match wins:

1. the `STATUSLINE_THEME` environment variable;
2. a `theme = <name>` line in the first readable config file among
   `$XDG_CONFIG_HOME/statuslines/config` (defaulting to `~/.config/statuslines/config`) and
   `~/.claude/statuslines.conf`;
3. `default`.

An unknown or malformed name falls back to `default` and writes
`statusline: unknown theme <name>, using default` to stderr. Claude Code discards stderr, so that
message is only visible when the script is run by hand — which is why the fallback renders a
working line rather than nothing.

### 2.2 Which file

The name is validated against `[A-Za-z0-9_-]+` before it touches a path — it can arrive from an
environment variable — and then `<name>.conf` is looked for in:

1. `$XDG_CONFIG_HOME/statuslines/themes/` (defaulting to `~/.config/statuslines/themes/`)
2. `~/.claude/statuslines/themes/`
3. `<repo>/themes/`

First hit wins, so **a user theme shadows a shipped theme of the same name**. Dropping your own
`default.conf` into `~/.config/statuslines/themes/` replaces the shipped one without touching the
clone, and survives a `git pull`.

One consequence of the order in §2.1 worth knowing: the config file is only read when
`STATUSLINE_THEME` is unset. When it is read, its keys land in the same namespace the theme file
will populate, and the theme file is loaded afterwards — so a theme's value wins over a config
file's value for the same key. Setting `STATUSLINE_THEME` skips the config file entirely, keys and
all.

---

### Segment resolution

Segments are looked up the same way themes are, user directories first:

1. `$XDG_CONFIG_HOME/statuslines/segments/<name>.sh` (default `~/.config/statuslines/segments/`)
2. `~/.claude/statuslines/segments/<name>.sh`
3. the shipped `lib/segments/<name>.sh`

A user segment of the same name shadows a shipped one, so a segment can be
overridden without editing the repository.

> **A segment directory is not a theme directory, and the difference matters.**
>
> A theme is *data*: it is parsed, never sourced, so installing one someone
> handed you cannot run their code (`docs/adr/0001-theme-config-format.md`).
>
> A segment is *code*. Loading one means sourcing it into the rendering shell,
> on every render, with your privileges. Putting a file in a segment directory
> is equivalent to installing a plugin and carries the same trust requirement.
> The two directories are named and documented separately for exactly this
> reason — do not merge them into one "extensions" directory.

A theme that names a segment which cannot be found renders `?<name>` in its
slot rather than omitting it silently, so a theme written for a machine that has
a user segment degrades visibly on a machine that does not.

## 3. Segments

One file per segment in `lib/segments/`, each exporting exactly one `segment_<name>` function.
A segment writes its fragment to stdout and returns `1` to mean "nothing to show" — which is a
normal state, not an error. Segments named in a `line<N>` key that do not exist are skipped.

A segment that *fails* — a missing file, a syntax error, an exit status above `1` — is different,
and renders as `?<name>` in its slot rather than as nothing. Without that, a crashed segment and a
quiet one look identical, and a theme can appear to be working while silently missing a segment.
Themes control the marker with `error_marker` and `error_color`.

| Segment | Shows | Payload fields read | Renders nothing when | Theme keys |
|---|---|---|---|---|
| `dir` | Working directory, `$HOME` collapsed to `~` | `workspace.current_dir`, falling back to `cwd` | the directory is absent | `dir_style`, `dir_depth`, `dir_color` |
| `git` | Branch name, e.g. `feat/theme-engine`; `@a1b2c3d` when detached; a marker when in a worktree | `worktree.branch`; otherwise `.git/HEAD` read from the filesystem, plus `workspace.git_worktree` / `worktree.name` for the marker | no `.git` is found walking up from the directory, or `HEAD` is unreadable | `git_color`, `git_worktree_marker` |
| `model` | Model name, plus `fast` and `nothink` labels | `model.display_name` falling back to `model.id`, `fast_mode`, `thinking.enabled` | no model name | `model_color`, `model_show_modes`, `model_fast_color` |
| `agent` | Agent name in brackets, `[reviewer]` | `agent.name` | no agent (the common case) | `agent_color` |
| `session` | The session's name | `session_name` | the session is unnamed — auto-generated display names do not populate this, so absence is normal | `session_color` |
| `effort` | Reasoning effort, `e:high` | `effort.level` | the model has no effort parameter | `effort_low_color`, `effort_medium_color`, `effort_high_color`, `effort_max_color` |
| `context` | Context window fullness, `ctx 47%`; `ctx+` on an extended-context model; an optional bar; `200k+` marker | `context_window.used_percentage`, `context_window.context_window_size`, `exceeds_200k_tokens` | never — an unknown value renders as `ctx --` | `context_label`, `context_warn`, `context_crit`, `context_unknown_color`, `context_bar`, `context_bar_width`, `context_bar_full`, `context_bar_empty` |
| `cost` | Session spend, `$3.42` (four decimals below $1) | `cost.total_cost_usd` | the field is absent or not numeric | `cost_color` |
| `burn` | Spend rate, `$2.50/h` | `cost.total_cost_usd`, `cost.total_duration_ms` | the session is younger than `burn_min_ms`, or spend rounds to zero cents | `burn_min_ms`, `burn_warn`, `burn_crit` |
| `duration` | Wall clock since session start, `1h22m` | `cost.total_duration_ms` | duration is zero or absent | `duration_color` |
| `delta` | Lines changed, `+418/-96` | `cost.total_lines_added`, `cost.total_lines_removed` | nothing has changed | `delta_add_color`, `delta_del_color` |
| `cache` | Prompt-cache hit ratio, `cache 88%` | `context_window.current_usage.cache_read_input_tokens`, `.cache_creation_input_tokens`, `.input_tokens` | before the first API call, when the denominator is zero | none — thresholds are fixed at 50/80 |
| `api` | Share of wall clock spent waiting on the API, `api 42%` | `cost.total_api_duration_ms`, `cost.total_duration_ms` | either is zero, or the share rounds to 0% | none — thresholds are fixed at 50/80 |
| `tokens` | Latest response's input/output tokens in thousands, `tok 144k/3k` | `context_window.total_input_tokens`, `context_window.total_output_tokens` | both are zero | `tokens_color` |
| `ratelimit` | Quota consumption with countdown and pace, `5h 41%(1h57m) under20` | `rate_limits.five_hour.used_percentage`, `.resets_at`, and the `seven_day` pair when enabled | no `rate_limits` in the payload — it is Pro/Max only, and only after the first API response | `ratelimit_5h_label`, `ratelimit_7d_label`, `ratelimit_show_7d`, `ratelimit_show_reset`, `ratelimit_pace`, `ratelimit_pace_threshold`, `ratelimit_warn`, `ratelimit_crit` |
| `pr` | Open pull request or merge request with review state, `#128 review` / `!77 ok` | `pr.number`, `pr.kind`, `pr.review_state` | there is no open PR for the branch | `pr_color` |
| `vim` | Current vim mode, `INSERT` | `vim.mode` | vim mode is off | none — colors are fixed per mode |

Notes that are easy to get wrong:

- **`git` never runs `git`.** It walks up from the working directory looking for `.git`, handles the
  linked-worktree form where `.git` is a file containing `gitdir: <path>`, and reads `HEAD`. That is
  one file read instead of a process spawn, and it removes any possibility of contending for a
  repository lock while the user is mid-commit.
- **`context` is the one segment that always renders.** `used_percentage` is `null` before the first
  API call and again immediately after `/compact`. That is *unknown*, not 0%, and it renders as
  `ctx --`. The same applies to a wrong-typed value. Rendering it as `ctx 0%` would be a
  confidently wrong number, which is worse than an omitted one.
- **`ctx+` is not decoration.** The label gains a `+` when `context_window_size` exceeds 200000,
  because 40% of 1M is a different situation from 40% of 200k.
- **The `200k+` marker is not "nearly full".** `exceeds_200k_tokens` uses a fixed 200k threshold and
  *includes* output tokens, so on a 1M-context model it fires at roughly 20% window use. It is shown
  as a separate marker precisely so it is not mistaken for the percentage.
- **`burn` thresholds are in cents per hour.** `burn_warn = 500` means $5.00/h. The segment does
  integer math in cents to stay free of `bc` and of float surprises.
- **`ratelimit` percentages are floats** in the payload (`23.5`), the only ones that are; the
  segment reads them with the float-tolerant helper and displays the integer part.
- **`pr` spells the state out.** `approved` renders as ` ok`, `changes_requested` as ` changes`,
  `pending` as ` review`, `draft` as ` draft` — colored too, but never colored *only*.
- **`vim` doubles up by default.** Claude Code draws its own `-- INSERT --` unless
  `statusLine.hideVimModeIndicator` is `true` in `settings.json`. Enabling this segment without
  setting that option shows the mode twice.

---

## 4. Theme keys

Every key below is read by the renderer or by a segment. Anything else in a theme file is inert.

### 4.1 Metadata

These are declarative: they are parsed and available, but no code branches on them. They exist so a
theme can describe itself to a human and to `make demo`.

| Key | Default | Meaning |
|---|---|---|
| `name` | — | The theme's own name. Should match the filename |
| `description` | — | One line describing the theme |
| `requires` | — | `none`, or what the theme needs: `nerdfont`, `truecolor`. A theme using glyphs a stock font lacks MUST declare it here and in this document |

### 4.2 Layout

| Key | Default | Meaning |
|---|---|---|
| `line1` … `line9` | empty | Whitespace-separated segment names, in order. An empty or absent line is skipped; lines are emitted in numeric order with a `\n` between them and no trailing newline. Nine is the ceiling the renderer scans to |
| `separator` | `" \| "` | Placed between rendered segments. **Quote it** — see §1.1 |
| `separator_color` | `dim` | Color for the separator |
| `width_reserve` | `0` | Columns to leave unclaimed. Subtracted from `COLUMNS` before fitting. All shipped themes use `6`, because Claude Code renders its own auto-compact notice beside the status line |
| `drop_order` | empty | Whitespace-separated segment names, first to be dropped first. Empty means right to left. See §7 |
| `error_marker` | `?` | Prefix for the marker shown in place of a segment that is broken or that the theme names but does not exist. The segment name follows it, so a broken `cost` renders as `?cost` |
| `error_color` | `red` | Color for that marker. The marker is text, so it stays legible with color off |

### 4.3 Global

| Key | Default | Meaning |
|---|---|---|
| `color` | unset | `off` / `none` / `0` disables color for the whole line; `on` / `always` / `1` forces it. An explicit `STATUSLINE_COLOR` or `NO_COLOR` in the environment still wins. A global switch is needed because segments choose some of their own colors — threshold ramps and dim labels are decided in code — so setting every `*_color` key to `none` would not produce a colorless line |
| `theme` | — | Only meaningful in the **config file**, not in a theme file. Names the theme to load |

### 4.4 Segment keys

| Key | Default | Meaning |
|---|---|---|
| `dir_style` | `basename` | `full`, `basename`, or `short`. `short` keeps the last `dir_depth` components and prefixes `.../` when it truncated |
| `dir_depth` | `2` | Components kept by `dir_style = short`. Non-numeric falls back to `2` |
| `dir_color` | `blue` | |
| `git_color` | `green` | |
| `git_worktree_marker` | `+wt` | Appended, space-separated, when the session is in a git worktree. The default is glyph-free so it survives the no-Nerd-Font rule; `powerline` sets it to `⧉` |
| `model_color` | `magenta` | |
| `model_show_modes` | `1` | `1` shows the `fast` and `nothink` labels; anything else suppresses them |
| `model_fast_color` | `cyan` | Color of the `fast` label. The `nothink` label is always `dim` |
| `agent_color` | `bright_magenta` | |
| `session_color` | `cyan` | |
| `effort_low_color` | `dim` | |
| `effort_medium_color` | `green` | |
| `effort_high_color` | `yellow` | |
| `effort_max_color` | `red` | Used for both `xhigh` and `max`. An unrecognized level renders `dim` and is not configurable |
| `context_label` | `ctx` | Gains a `+` suffix when the context window is larger than 200000 |
| `context_warn` | `60` | Percent at which the number turns yellow |
| `context_crit` | `85` | Percent at which the number turns red |
| `context_unknown_color` | `dim` | Color of the `--` shown when the percentage is unknown |
| `context_bar` | `0` | `1` draws a bar beside the number. The number is always printed too — the bar is decoration and never the sole carrier of the value |
| `context_bar_width` | `10` | Bar width in characters. Non-numeric falls back to `10` |
| `context_bar_full` | `#` | Filled cell |
| `context_bar_empty` | `.` | Empty cell |
| `cost_color` | `yellow` | |
| `burn_min_ms` | `60000` | Suppress the burn rate until the session is this old. Dividing a few cents by a few seconds produces an alarming, meaningless number |
| `burn_warn` | `500` | Cents per hour at which the rate turns yellow ($5.00/h) |
| `burn_crit` | `1500` | Cents per hour at which the rate turns red ($15.00/h) |
| `duration_color` | `cyan` | |
| `delta_add_color` | `green` | |
| `delta_del_color` | `red` | |
| `tokens_color` | `cyan` | The `tok ` label is always `dim` |
| `ratelimit_5h_label` | `5h` | |
| `ratelimit_7d_label` | `7d` | |
| `ratelimit_show_7d` | `0` | `1` also renders the seven-day window |
| `ratelimit_show_reset` | `1` | `1` appends the countdown to reset, `(1h57m)` |
| `ratelimit_pace` | `1` | `1` appends the pace marker, `over12` or `under20` |
| `ratelimit_pace_threshold` | `5` | Percentage points of deviation before the pace marker appears at all |
| `ratelimit_warn` | `70` | Percent at which quota turns yellow |
| `ratelimit_crit` | `90` | Percent at which quota turns red |
| `pr_color` | `blue` | Used only when the review state is absent or unrecognized. `approved`, `changes_requested`, `pending`, and `draft` set green, red, yellow, and dim respectively and are not configurable |

The `cache`, `api`, and `vim` segments read no theme keys. Their thresholds and mode colors are
fixed. Per `docs/CODING-STANDARDS.md` §6.2, a key does not ship until a shipped theme uses it, so
if you need one of these configurable, add the key and the theme that exercises it in the same
change.

**Pace, specifically.** `ratelimit` compares consumption against the share of the window that has
already elapsed:

```
elapsed_share = (window_minutes - minutes_remaining) / window_minutes
pace          = used_percentage - elapsed_share * 100
```

`window_minutes` is 300 for the five-hour window and 10080 for the seven-day one. Positive means
burning quota faster than the window replenishes it. This is the number worth showing, because a
raw `used_percentage` early in a window is alarming and meaningless.

---

## 5. Color vocabulary

A color value is one of these names. `lib/colors.sh` is the only file in the repository permitted
to contain an escape literal; a theme names a color and never spells one.

**Attributes:** `reset` `bold` `dim` `italic` `underline` `reverse`

**Colors:** `black` `red` `green` `yellow` `blue` `magenta` `cyan` `white`

**Bright colors:** `bright_black` (also `gray`, `grey`) `bright_red` `bright_green`
`bright_yellow` `bright_blue` `bright_magenta` `bright_cyan` `bright_white`

**`none`** means "emit this text unpainted". It is not the same as an empty value, which falls back
to the built-in default (§1.3).

An unrecognized name yields no color rather than an error: a typo in a theme should cost you a
color, not the whole status line.

### 5.1 Why only these sixteen

Because the terminal's background is not ours to know.

The 16 standard SGR colors are indirect: the user's own terminal theme decides what `blue` actually
renders as, and every terminal theme worth using picks a value readable against its own background.
A hardcoded 256-color or truecolor value bypasses that entirely. `\033[38;5;236m` looks like a
tasteful dark gray on the author's machine and is invisible on a dark background — and the failure
is silent, because the text is there, just unreadable.

A theme that genuinely needs truecolor MAY use it, but MUST declare `requires = truecolor` and MUST
NOT be the default. See `docs/CODING-STANDARDS.md` §8.

---

## 6. Accessibility rules

These are requirements, not suggestions. A theme that fails one of them does not ship.

1. **Color MUST NOT be the sole carrier of meaning.** A context gauge that turns red at 90% must
   also print `90%`. A cache health indicator must print the ratio. A PR that is approved must say
   `ok`, not merely be green. A red dot and a green dot are the same dot to a colorblind user and
   to a monochrome terminal. This is why every colored value in the shipped themes is also a
   printed number or word.
2. **The default theme MUST render correctly in a font with no special glyphs**, and MUST NOT use
   emoji. Emoji width handling is inconsistent across terminals and misaligns the line, which
   breaks the width fitting in §7 as well as the layout.
3. **A theme requiring special glyphs MUST declare `requires`** — in the theme file and in the
   table in this document. `powerline` sets `requires = nerdfont` because its U+E0B1 separator and
   its block-character context bar render as tofu boxes without one. That makes it a choice rather
   than a surprise.
4. **`NO_COLOR` MUST survive.** Any non-empty `NO_COLOR` disables color regardless of what the theme
   says. A theme MUST NOT be unreadable with color stripped — run it under `NO_COLOR=1` and check
   that no information disappeared.
5. **Width is measured in display columns, not bytes.** Truncating by byte count cuts a multibyte
   character in half and corrupts the line.

The `plain` theme is the executable form of rules 1 and 4. It sets `color = off` and the test suite
asserts that its output contains zero escape bytes — if that assertion ever fails, the
accessibility claim in this document is false.

---

## 7. Width fitting

Claude Code exports `COLUMNS` (v2.1.153+). `tput cols` does not work here because stdout is a pipe
into Claude Code rather than the terminal, and falling back to a hardcoded 80 is the single most
common width bug in status line scripts. When `COLUMNS` is absent or non-numeric, fitting is
skipped rather than guessed at, and the line is printed in full.

The algorithm, per line:

1. Compute the usable width: `COLUMNS - width_reserve`.
2. Render every segment, join with the separator, and measure the result **with color stripped** —
   escape sequences occupy zero columns.
3. If it fits, print it.
4. Otherwise walk `drop_order`, blanking one segment at a time and re-measuring after each, until
   it fits or only one segment is left standing.

Two properties fall out of that, and both are deliberate:

- **Whole segments are dropped; nothing is truncated mid-segment.** A half-cut segment reads as
  terminal corruption and sends the user looking for a bug. A missing segment reads as a missing
  segment.
- **The last surviving segment is never dropped.** An empty line reads as "the status line is
  broken"; a cramped one does not.

`drop_order` is a plain list of segment names, first to go listed first. A name not on the line is
harmless. A name omitted from `drop_order` is never dropped. When `drop_order` is unset the default
is right to left, which is usually right — but only usually, which is why every shipped theme states
it explicitly.

`width_reserve` exists because the full terminal width is not actually ours to fill: Claude Code
renders its own auto-compact notice alongside the status line. All shipped themes reserve `6`.

### 7.1 Worked example

`themes/default.conf` declares:

```
line1 = dir git model context cost duration delta
width_reserve = 6
drop_order = delta duration cost context model git dir
```

The full line is 72 columns. Narrowing the terminal:

```
COLUMNS=140   acme-api | feat/theme-engine | Opus | ctx 47% | $3.42 | 1h22m | +418/-96
COLUMNS=60    acme-api | feat/theme-engine | Opus | ctx 47% | $3.42
COLUMNS=40    acme-api | feat/theme-engine
COLUMNS=20    acme-api
```

Step by step at `COLUMNS=60`: usable width is `60 - 6 = 54`. The full 72 does not fit, so `delta`
goes first — 61, still too wide — then `duration`, giving 53, which fits. `cost` survives even
though it sits to the right of `context`, because `drop_order` is a priority list and not a
direction.

At `COLUMNS=20` the usable width is 14 and nothing but `acme-api` fits. `dir` is last in
`drop_order` and is also the last survivor, so the loop stops there rather than emitting an empty
line.

---

## 8. Build your own theme

### 8.1 Start from a shipped one

```sh
mkdir -p ~/.config/statuslines/themes
cp themes/minimal.conf ~/.config/statuslines/themes/focus.conf
```

Your directory is searched before the repo's, so this also lets you override a shipped theme by
keeping its filename.

### 8.2 Iterate without launching Claude Code

Rendering is a pure function of the payload, the theme, and a small set of environment variables,
so you can drive it directly. Save a payload once and pipe it in:

```sh
printf '%s' "$(cat payload.json)" \
  | COLUMNS=120 SL_NOW=1755490000 STATUSLINE_THEME=focus bash statusline.sh
```

- `COLUMNS` sets the width, so you can test the drop order without resizing anything.
- `SL_NOW` pins the clock in Unix seconds, so the quota countdown and the pace marker stop moving
  between runs. Without it they change every render and you cannot tell a layout change from a
  clock tick.
- `NO_COLOR=1` shows you what the theme looks like with color stripped, which is rule 4 of §6.

### 8.3 Choose the line

Pick the segments, in order. Keep in mind which ones are usually silent — `agent`, `session`,
`vim`, `pr`, and `ratelimit` render nothing in most sessions, so a theme built around them looks
empty on a normal day.

```
line1 = dir git context ratelimit
```

### 8.4 Set the separator, quoted

```
separator       = " · "
separator_color = dim
```

### 8.5 Configure the segments

Only the keys you want to change from their defaults; §4.4 has the full list.

```
dir_style = short
dir_depth = 2
dir_color = bright_blue

git_color           = green
git_worktree_marker = +wt

context_label     = ctx
context_warn      = 55
context_crit      = 80
context_bar       = 1
context_bar_width = 8

ratelimit_5h_label   = 5h
ratelimit_show_reset = 1
ratelimit_pace       = 1
```

### 8.6 Decide what to sacrifice

```
width_reserve = 6
drop_order    = ratelimit context git dir
```

Quota goes first because it is the least urgent thing on the line; the directory goes last because
without it you do not know what you are looking at.

### 8.7 The complete file

Copy this into `~/.config/statuslines/themes/focus.conf` and select it with
`STATUSLINE_THEME=focus`:

```
# focus — directory, branch, context, and quota. Nothing else.
name        = focus
description = Directory, branch, context and 5h quota
requires    = none

line1 = dir git context ratelimit

separator       = " · "
separator_color = dim

dir_style = short
dir_depth = 2
dir_color = bright_blue

git_color           = green
git_worktree_marker = +wt

context_label     = ctx
context_warn      = 55
context_crit      = 80
context_bar       = 1
context_bar_width = 8

ratelimit_5h_label   = 5h
ratelimit_show_reset = 1
ratelimit_pace       = 1

width_reserve = 6
drop_order    = ratelimit context git dir
```

Rendered against a session with an active five-hour window, at three widths (color stripped):

```
COLUMNS=120   .../code/acme-api · feat/theme-engine · ctx 47% ###..... · 5h 41%(1h57m) under20
COLUMNS=60    .../code/acme-api · feat/theme-engine
COLUMNS=34    .../code/acme-api
```

### 8.8 Before proposing it upstream

A theme in your own config directory is yours and needs to satisfy nobody. A theme in `themes/` is
shipped, and shipped means:

- `name`, `description`, and `requires` are set, and `requires` is honest.
- Only the 16 standard color names are used (§5), unless `requires` says otherwise.
- Every value is readable under `NO_COLOR=1` (§6).
- `drop_order` and `width_reserve` are set, and checked at `COLUMNS=80` and `COLUMNS=40`.
- A golden file exists for it against the committed fixtures.
- It has a row in the theme table in `README.md` and its keys are documented here.

`CONTRIBUTING.md` has the rest of the process.

---

## Version History

| Date | Version | Change |
|------|---------|--------|
| 2026-08-17 | 1.0.0 | Initial reference, covering the 17 shipped segments and the 5 shipped themes |
