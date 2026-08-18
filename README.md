# statuslines

A themeable status line engine for [Claude Code](https://code.claude.com/docs/en/statusline), written in Bash.

[![CI](https://github.com/williamzujkowski/statuslines/actions/workflows/ci.yml/badge.svg)](https://github.com/williamzujkowski/statuslines/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Claude Code pipes a JSON blob describing your session to a command of your choosing and renders
whatever that command writes to stdout, beneath the prompt. This is that command.

Four things make it different from the shell one-liner most people start with:

- **Themes are declarative, and are parsed rather than sourced.** A theme is a `key = value` text
  file. Installing one someone handed you is not the same as running their code, which is what
  makes themes safe to accept as pull requests.
- **It never invokes `git`.** The branch comes from reading `.git/HEAD` off the filesystem. That
  saves a process spawn, and more importantly it means the status line can never contend for a
  repository lock while you are mid-commit.
- **It degrades visibly instead of vanishing.** An unparseable payload prints
  `statusline degraded: unparseable payload`, not a blank line. A context window that has not been
  measured yet prints `ctx --`, not `ctx 0%`. A line too wide for the terminal loses whole
  segments in a documented order rather than being cut off mid-word.
- **It is tested with golden files, including against hostile payloads.** Rendering is a pure
  function of payload, theme, and a small declared set of environment variables, so the expected
  output of every (fixture, theme) pair is committed and diffed.

Version 0.1.0 <!-- x-release-please-version -->

---

## What it looks like

All four examples below are real output for the same session, captured by piping a fixture
through `statusline.sh`. ANSI escapes have been stripped so they read as text here; in a terminal
the directory is blue, the branch green, the model magenta, and the context and quota percentages
are colored by threshold.

`default` — balanced, one line, no font requirements:

```
acme-api | feat/theme-engine | Opus | ctx 47% | $3.42 | 1h22m | +418/-96
```

`minimal` — the four things you actually look at:

```
acme-api · feat/theme-engine · ctx 47% · $3.42
```

`dashboard` — two lines, everything the payload offers:

```
.../code/acme-api | feat/theme-engine | Opus | [reviewer] | e:high | ctx 47% ####...... | #128 review
$3.42 | $2.50/h | 1h22m | +418/-96 | cache 88% | api 42% | tok 144k/3k | 5h 41%(1h57m) under20 7d 63%(72h0m) over6
```

`plain` — no color, no glyphs, nothing but text. This is also the accessibility baseline and the
theme the test suite asserts emits zero escape bytes:

```
acme-api | feat/theme-engine | Opus | ctx 47% | $3.42 | 1h22m | +418/-96
```

There is a fifth shipped theme, `powerline`, which uses U+E0B1 separators and block-character
context bars. It requires a patched Nerd Font and says so in its own `requires` key.

---

## Install

Clone it anywhere:

```sh
git clone https://github.com/williamzujkowski/statuslines.git ~/git/statuslines
```

Point `~/.claude/settings.json` at it:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/git/statuslines/statusline.sh"
  }
}
```

Start a new Claude Code session. There is no build step and nothing is installed outside the
clone.

## Quick start

Try a theme before committing to it:

```sh
STATUSLINE_THEME=dashboard claude
```

Render one against a payload without launching Claude Code at all:

```sh
printf '{"cwd":"/home/user/code/acme-api","model":{"display_name":"Opus"}}' \
  | COLUMNS=140 STATUSLINE_THEME=minimal bash statusline.sh
```

That prints `acme-api · ctx --` — the model is shown, the context window is unknown because the
payload did not carry it, and it says so rather than guessing.

`make demo` renders every shipped theme at once.

## Choosing a theme

The theme is resolved in this order, first match wins:

1. the `STATUSLINE_THEME` environment variable;
2. a `theme = <name>` line in `~/.config/statuslines/config` (or `$XDG_CONFIG_HOME/statuslines/config`),
   or in `~/.claude/statuslines.conf`;
3. `default`.

An unknown theme name is a configuration error you need to see, but not a reason to show nothing:
it falls back to `default` and writes `statusline: unknown theme <name>, using default` to stderr.

| Theme | Layout | Requires | Shows |
|---|---|---|---|
| `default` | one line | nothing | dir, branch, model, context, cost, duration, lines changed |
| `minimal` | one line | nothing | dir, branch, context, cost |
| `plain` | one line | nothing | same as `default`, with `color = off` globally |
| `dashboard` | two lines | nothing | everything: agent, effort, PR, burn rate, cache hit ratio, API share, tokens, quota with pace |
| `powerline` | one line | a Nerd Font | dir, branch, model, context bar, cost, duration, with U+E0B1 separators |

`plain` exists for three audiences: terminals and pipes that cannot render color, anyone who sets
`NO_COLOR`, and the test suite, where it is the proof that every value survives with color
stripped.

## Configuration

### Environment

| Variable | Effect |
|---|---|
| `STATUSLINE_THEME` | Theme name. Beats the config file |
| `NO_COLOR` | Any non-empty value disables color ([no-color.org](https://no-color.org/)) |
| `STATUSLINE_COLOR` | `0`/`off`/`never` or `1`/`on`/`always`. Beats both `NO_COLOR` and the theme's own `color` key |
| `SL_NOW` | Unix seconds, substituted for the current time. Exists so anything time-dependent — the quota countdown, the pace calculation — is deterministic under test |

`COLUMNS` is exported by Claude Code itself (v2.1.153+) and is the only width signal available;
`tput cols` does not work here because stdout is a pipe, not the terminal. When `COLUMNS` is
absent, width fitting is skipped rather than guessed at.

### Config file

Read from `$XDG_CONFIG_HOME/statuslines/config` (defaulting to `~/.config/statuslines/config`),
falling back to `~/.claude/statuslines.conf`. The first readable one wins. It uses the same
`key = value` syntax as a theme file:

```
# ~/.config/statuslines/config
theme = dashboard
```

Only `theme` is meaningful here today. Everything else belongs in a theme file.

### settings.json keys worth knowing

Claude Code accepts three optional keys alongside `command`:

| Key | Type | Why you might want it |
|---|---|---|
| `padding` | number | Extra horizontal indent, in characters |
| `refreshInterval` | number | Seconds between timer-driven re-runs, minimum `1` |
| `hideVimModeIndicator` | boolean | Set `true` if you enable the `vim` segment, or the mode shows twice |

`refreshInterval` matters more than it looks. Event triggers go quiet while a session is idle, so
without it the quota countdown in `dashboard` freezes at whatever it said when the last message
landed. Five seconds is a reasonable value:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/git/statuslines/statusline.sh",
    "refreshInterval": 5,
    "hideVimModeIndicator": true
  }
}
```

There is **no `timeout` key**. Several community writeups show one; it does not exist in the
schema, and unknown keys are ignored silently, so a config containing it looks accepted and does
nothing. What actually bounds runtime is cancellation — see *How it works* below.

## Writing your own theme

Copy a shipped theme out of `themes/` into `~/.config/statuslines/themes/`, edit it, and select it
by name. A theme in your own directory shadows a shipped one with the same filename, so you can
override `default` without touching the clone.

```sh
mkdir -p ~/.config/statuslines/themes
cp themes/minimal.conf ~/.config/statuslines/themes/focus.conf
STATUSLINE_THEME=focus claude
```

The format is `key = value` with `#` comments. One rule catches everyone: values are trimmed
unless quoted, so anything whose leading or trailing spaces matter — in practice, `separator` —
must be quoted. `separator = " | "` gives you `a | b`; `separator = |` gives you `a|b`.

[`docs/THEMES.md`](docs/THEMES.md) is the reference: every segment, every theme key with its
default, the color vocabulary, the accessibility rules, and a build-your-own walkthrough.

## Requirements

- `bash` 3.2 or newer
- `jq`

That is the complete list. `git` is not required at render time and is never invoked.

## Compatibility

**macOS.** Stock macOS ships `bash` 3.2.57 and always will, so 3.2 is the floor: no associative
arrays, no `${var,,}`, no `mapfile`, no `**`. CI enforces this with a job that asserts
`/bin/bash` really is 3.2 and then runs the whole suite under it — without that job the rule is
unenforced folklore.

**Linux.** Tested on `ubuntu-latest` and `ubuntu-22.04` in CI.

**Windows.** The command runs under Git Bash when it is installed. Backslashes in the `command`
string are consumed as escapes before the script ever runs, so write the path with forward
slashes:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash C:/Users/you/git/statuslines/statusline.sh"
  }
}
```

**Older Claude Code.** Every payload field is treated as optional with an explicit default, so no
segment requires a particular version. A field your client does not send renders as unknown or
not at all, and the rest of the line is unaffected.

## How it works

**One `jq` call.** `lib/core.sh` runs a single `jq` program that extracts every field the engine
knows about, strips control characters from each value, and emits them RS-delimited for one bash
read loop. Spawning `jq` per field is the largest latency mistake available in a status line, and
it is the one this project was rewritten to stop making.

**Absent is not zero.** Fields that the payload did not carry are marked with a sentinel rather
than defaulted to `0`. A `used_percentage` of `null` — which is what Claude Code sends before the
first API call and immediately after `/compact` — renders as `ctx --`. Rendering it as `ctx 0%`
would be a confidently wrong number, which is worse than an omitted one.

**Segment isolation.** Each segment is one file in `lib/segments/` exporting exactly one
`segment_<name>` function. It writes its fragment to stdout and returns non-zero to mean "I have
nothing to show". It does not know about separators, about the other segments, or about the
terminal width. A segment that fails is contained to its own slot and cannot abort the render.

**Width fitting by dropping.** The renderer measures the finished line with color stripped, and if
it exceeds `COLUMNS` minus the theme's `width_reserve` it removes whole segments in the theme's
`drop_order` (right to left by default) until it fits. It never truncates mid-segment — a half-cut
segment reads as terminal corruption, while a missing one reads as a missing segment — and it never
drops the last survivor. Narrowing a terminal against the `default` theme walks through this:

```
COLUMNS=140   acme-api | feat/theme-engine | Opus | ctx 47% | $3.42 | 1h22m | +418/-96
COLUMNS=60    acme-api | feat/theme-engine | Opus | ctx 47% | $3.42
COLUMNS=40    acme-api | feat/theme-engine
COLUMNS=20    acme-api
```

**Why latency is a correctness rule.** Claude Code debounces status line runs by 300 ms and
*aborts* an in-flight run when a new trigger arrives — an abort, not a queue, so whatever the
script had already written is discarded. A slow status line therefore does not render late; during
an active turn it renders nothing at all, with no error anywhere. That is why the budget is under
100 ms warm and at most four process spawns per render, and why it is enforced by a CI job rather
than left to taste.

## Contributing

[`CONTRIBUTING.md`](CONTRIBUTING.md) has the bootstrap, the commit conventions, and the recipes for
adding a segment or a theme. In short: `make setup` installs the dev tooling and the commit hook,
`make check` is the gate, and the PR *title* is what CI validates because `main` is squash-merged.

The behavioral contract for AI coding agents working in this repository is
[`AGENTS.md`](AGENTS.md), adapted from the
[GSA-TTS Agentic Coding Playbook](https://github.com/GSA-TTS/agentic-coding-playbook). It is
binding on agents and worth reading if you want to know why the code is shaped this way. The craft
detail behind it lives in [`docs/CODING-STANDARDS.md`](docs/CODING-STANDARDS.md), and the
field-by-field description of the payload is in
[`docs/STATUSLINE-CONTRACT.md`](docs/STATUSLINE-CONTRACT.md).

Versioning is semver, driven by [release-please](https://github.com/googleapis/release-please) from
Conventional Commits. `CHANGELOG.md` and `version.txt` are generated and must never be hand-edited.

## License

MIT. See [`LICENSE`](LICENSE).

## Attribution

`AGENTS.md` and `docs/CODING-STANDARDS.md` are adapted from the
[GSA-TTS Agentic Coding Playbook](https://github.com/GSA-TTS/agentic-coding-playbook)
(public domain / CC0), with the federal compliance scaffolding removed and the engineering
discipline kept.
