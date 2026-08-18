---
title: "statuslines — Status Line Contract"
description: "Authoritative field-by-field reference for the JSON payload Claude Code pipes to a statusLine command, plus invocation mechanics, presence semantics, and derived-value formulas"
status: canonical
tier: 1
last_updated: "2026-08-17"
related_files: ["../AGENTS.md", "CODING-STANDARDS.md", "THEMES.md", "../lib/core.sh", "../test/fixtures/"]
load_priority: "always"
review_cycle: "quarterly"
---

# Status Line Contract

This document describes the interface between Claude Code and this project: what arrives on
stdin, what Claude Code does with what we write to stdout, and when it runs us at all. It
exists so that no one working in this repository has to guess about a payload field, and so
that a wrong guess shows up as a documentation diff rather than as a confidently wrong number
in a user's terminal.

`AGENTS.md` §4 is the binding rule set for render-path code. This document is the field-level
detail it defers to; where the two disagree, `AGENTS.md` wins and this file is the bug.

**Key words** — "MUST", "MUST NOT", "SHOULD", "SHOULD NOT", "MAY" — follow
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

**Verified against:** Claude Code 2.1.234 (payload builder and settings schema) and the
official reference at <https://code.claude.com/docs/en/statusline>. Where the two differ,
this document records the observed behavior and says so.

---

## 1. Configuration Surface

Claude Code reads the status line from `settings.json`. The schema below is the complete set
of accepted keys.

| Key | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `statusLine.type` | string | yes | — | `"command"` is the only permitted value |
| `statusLine.command` | string | yes | — | A script path or an inline shell fragment. Run through a shell, so quoting rules are the shell's |
| `statusLine.padding` | number | no | `0` | Extra horizontal indent in characters, added to the interface's own spacing. Relative indent, not absolute distance from the terminal edge |
| `statusLine.refreshInterval` | number | no | unset | Seconds between timer-driven re-runs, minimum `1`. Additive to the event triggers in §2. Requires v2.1.97+ |
| `statusLine.hideVimModeIndicator` | boolean | no | `false` | Suppresses the built-in `-- INSERT --` line. Set it when the script renders `vim.mode` itself, to avoid showing the mode twice |
| `subagentStatusLine.type` | string | yes | — | `"command"` |
| `subagentStatusLine.command` | string | yes | — | Separate command for subagent rows (§6) |

### 1.1 There is no `timeout` key

Several community READMEs and blog posts show a `"timeout": 10` entry inside `statusLine`.
**No such field exists in the schema.** It is neither validated nor honored — the parser
ignores unknown keys silently, so a configuration containing it looks accepted and does
nothing. Documentation in this repository MUST NOT show a `timeout` key, and an issue report
that includes one SHOULD be treated as a possible symptom of the reporter believing they had
a timeout guard when they did not.

The real mechanism that bounds script runtime is cancellation on the next trigger (§2.2),
which is a very different behavior: a timeout would let a slow script finish late, whereas
cancellation kills it and renders nothing.

---

## 2. Invocation Mechanics

This section drives the whole design of the engine, so it comes before the field reference.

### 2.1 Triggers

Claude Code re-renders the status line on:

- session start, including `--resume` and `--continue`;
- every new assistant message;
- completion of `/compact`;
- a permission-mode change;
- a vim-mode toggle;
- the `refreshInterval` timer, when configured.

Internally the re-render is keyed on the input set
`["tokenUsage", "permissionMode", "vimMode", "mainLoopModel", "fastMode", "effortValue",
"thinkingEnabled", "prStatus"]` plus the last assistant message id. The practical consequence
is that a PR status change re-fires the render even when nothing else moved, so the `pr.*`
segment does not need its own polling.

### 2.2 Debounce and cancellation

Updates are debounced at **300 ms**: bursts of triggers collapse into one run after the burst
stops. If a new trigger arrives while the script is still running, the in-flight run is
**aborted** — via an `AbortController`, not queued and not allowed to finish. Whatever it had
already written is discarded.

This is why the latency budget in `AGENTS.md` §4.4 is a **correctness rule and not a
nicety**. A script that takes longer than the interval between triggers is not merely slow;
during an active turn it is repeatedly killed and the user sees a stale line or no line at
all, with no error anywhere. A segment that cannot meet its budget MUST move behind a cache
with an explicit TTL rather than being allowed to run long.

### 2.3 Idle gaps

Event triggers go quiet while the main session is idle — most visibly while a coordinator
waits on background subagents. Any segment whose value changes on its own (a clock, a
countdown to a rate-limit reset, a quota display, anything sourced from a file another process
writes) MUST document that it needs `refreshInterval` to stay current, because no event will
wake it.

### 2.4 Environment

Claude Code exports `COLUMNS` and `LINES` from its own `process.stdout` before running the
command (v2.1.153+), along with `CLAUDE_PROJECT_DIR`.

`tput cols` and any `isatty` check **do not work**, because our stdout is a pipe into Claude
Code, not the terminal. This is the single most common width bug in status line scripts: the
script falls back to a hardcoded 80 columns, or to `tput`'s error path, and truncates
correctly-sized output. Width MUST be read from `COLUMNS`, with a documented fallback for
Claude Code versions older than 2.1.153.

### 2.5 Output

- **stdout only.** stderr is captured and discarded. A diagnostic written only to stderr is
  invisible, which is why `AGENTS.md` §4.2 forbids stderr as the sole signal of a problem.
- **Multi-line is supported**, one row per output line. There is no documented cap on the
  number of lines. A line longer than the terminal width used to corrupt neighboring rows;
  that was fixed in v2.1.141, but this project still bounds line length (`AGENTS.md` §4.2)
  because older clients are in the wild.
- **ANSI SGR is supported**, including truecolor where the terminal supports it. This project
  restricts itself to the 16 standard SGR colors by default per `CODING-STANDARDS.md` §8.
- **OSC 8 hyperlinks** work on iTerm2, Kitty, and WezTerm; `FORCE_HYPERLINK=1` overrides
  Claude Code's terminal detection for emulators it does not recognize. When emitting escape
  sequences, `printf '%b'` MUST be used rather than `echo -e`, whose behavior varies by shell
  and which is the usual cause of literal `\e]8;;` appearing in the line. Note that
  `AGENTS.md` §4.2 forbids OSC sequences in this project's own output regardless of client
  support, because the status line is composited into a TUI that owns the screen.
- **Non-zero exit or empty output blanks the line.** This project always exits 0 and always
  prints something (`AGENTS.md` §4.5).

### 2.6 Gating

The status line is disabled, silently, in these cases:

| Condition | Behavior |
|---|---|
| Workspace not trusted | Command is skipped. `claude --debug` logs `Status line command skipped: workspace trust not accepted`. Security fix, v2.1.51 |
| `disableAllHooks: true` outside managed settings | Only a `statusLine` from managed settings runs; with none configured there, the status line is off |
| `allowManagedHooksOnly` in managed settings | A user's custom status line is replaced by the managed one with no warning |

`claude --debug` logs the exit code and stderr of the **first** invocation in a session. That
is the only built-in visibility into a failing script, and it covers the first run only, so a
script that fails intermittently will not show up there.

### 2.7 Windows

The command runs under Git Bash when it is installed, and PowerShell otherwise. Backslashes in
the `command` path are consumed as escape characters before the script runs, so the path MUST
be written with forward slashes. Install instructions in this repository MUST show the forward
slash form for Windows.

---

## 3. Payload Field Reference

Fields are listed in the order the v2.1.234 payload builder emits them. Order is not
semantically meaningful — it is recorded so that captured fixtures can be diffed against a
real payload without spurious reordering noise.

"Presence" values: **always** (every version that has the field), **absent** (key omitted
entirely under the stated condition), **nullable** (key present with a `null` value). §4
covers why the distinction matters.

### 3.1 Session identity

| Field | Type | Presence | Notes |
|---|---|---|---|
| `session_id` | string (UUID) | always | Stable for the session's lifetime, unique across sessions. The correct cache key (§5) |
| `transcript_path` | string | always | Path to the session's `.jsonl` transcript. Reveals the user's directory layout — MUST be scrubbed from committed fixtures |
| `cwd` | string | always | Same value as `workspace.current_dir`. Kept for compatibility; new code SHOULD prefer the `workspace` form |
| `prompt_id` | string (UUID) | absent until first user input | Matches the OpenTelemetry `prompt.id` attribute, so it can correlate a rendered line with a telemetry event. v2.1.196+ |
| `session_name` | string | absent when unnamed | From `--name`, `/rename`, or an AI-generated title. The default display name such as `my-app-3f` does **not** populate it, so absence is common and MUST NOT be rendered as an error |

### 3.2 Model

| Field | Type | Presence | Notes |
|---|---|---|---|
| `model.id` | string | always | e.g. `claude-opus-5` |
| `model.display_name` | string | always | e.g. `Opus`. Prefer for display; fall back to `model.id` |

### 3.3 Workspace

| Field | Type | Presence | Notes |
|---|---|---|---|
| `workspace.current_dir` | string | always | The session's current directory. **Preferred over top-level `cwd`** |
| `workspace.project_dir` | string | always | The directory Claude Code was launched in. Differs from `current_dir` after a `cd`, which is what makes a "project vs. current" segment possible |
| `workspace.added_dirs` | string[] | always (v2.1.47+) | From `/add-dir` and `--add-dir`. `[]` when none — an empty array, not an absent key |
| `workspace.git_worktree` | string | absent in the main tree | Worktree name for **any** linked worktree created with `git worktree add`. Distinct from `worktree.*` (§3.11). v2.1.97/98 |
| `workspace.repo.host` | string | absent without repo/origin | Parsed from the `origin` remote, e.g. `github.com` |
| `workspace.repo.owner` | string | absent without repo/origin | e.g. `anthropics` |
| `workspace.repo.name` | string | absent without repo/origin | e.g. `claude-code`. v2.1.145 |

`workspace.repo` is parsed by Claude Code from the remote URL, which means a repository
segment can render owner/name **without spawning `git`** — relevant to the ≤4 spawn budget.

### 3.4 Client

| Field | Type | Presence | Notes |
|---|---|---|---|
| `version` | string | always | Claude Code version. The only reliable way to know which fields to expect |
| `output_style.name` | string | always | Current output style |

### 3.5 Cost and duration

| Field | Type | Presence | Notes |
|---|---|---|---|
| `cost.total_cost_usd` | number | always | **Client-side estimate**, not a bill. Resets to `$0` when `/clear` starts a new session (v2.1.211). Any segment rendering it SHOULD avoid implying billing accuracy |
| `cost.total_duration_ms` | number | always | Wall-clock milliseconds since session start |
| `cost.total_api_duration_ms` | number | always | Milliseconds spent waiting on the API |
| `cost.total_lines_added` | number | always | Lines added this session |
| `cost.total_lines_removed` | number | always | Lines removed this session |

### 3.6 Context window

| Field | Type | Presence | Notes |
|---|---|---|---|
| `context_window.total_input_tokens` | number | always | `input + cache_creation + cache_read` of the **latest** response. `0` before the first API call |
| `context_window.total_output_tokens` | number | always | Output tokens of the latest response only |
| `context_window.context_window_size` | number | always | `200000`, or `1000000` for extended-context models |
| `context_window.used_percentage` | integer 0–100 | **nullable** | `Math.round((input + cache_creation + cache_read) / size * 100)`, clamped to 0–100. **Output tokens are excluded.** `null` before the first API call and immediately after `/compact` |
| `context_window.remaining_percentage` | integer 0–100 | **nullable** | `100 - used_percentage`, with the same null conditions |
| `context_window.current_usage` | object | **nullable** | `{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}`. `null` before the first API call and after `/compact` |

A manual percentage computed from `current_usage` MUST use the same input-only formula, or it
will disagree with `used_percentage` by the size of the last response and the two numbers will
visibly diverge in a theme that shows both.

Before v2.1.132 `context_window` was cumulative across the session rather than the current
window. Payloads captured from older clients are not comparable, and any fixture claiming to
come from a pre-2.1.132 client MUST say so in a comment.

### 3.7 The `exceeds_200k_tokens` trap

| Field | Type | Presence | Notes |
|---|---|---|---|
| `exceeds_200k_tokens` | boolean | always | True when the latest response's combined tokens exceed a **fixed 200k threshold** |

Two differences from `used_percentage` make this field easy to misuse:

1. It **includes output tokens**; `used_percentage` does not.
2. It uses a **fixed 200k threshold regardless of the real window size**.

On a 1M-context model the field therefore goes true at roughly 20% window use, and a theme
that treats it as "context nearly full" will scream at a session with 800k tokens of headroom.
Segments MUST derive fullness from `used_percentage` (or from `total_input_tokens` against
`context_window_size`) and MUST treat `exceeds_200k_tokens` only as what it literally is: a
200k marker.

### 3.8 Session modes

| Field | Type | Presence | Notes |
|---|---|---|---|
| `fast_mode` | boolean | always | Fast mode on/off |
| `effort.level` | string | absent when unsupported | `low`, `medium`, `high`, `xhigh`, or `max`. Live value, so a mid-session `/effort` change is reflected. Ultracode is not a separate level and reports as `xhigh`. Absent when the model has no effort parameter. v2.1.119 |
| `thinking.enabled` | boolean | always | Extended thinking on/off. Defaults to `true` |

### 3.9 Rate limits

| Field | Type | Presence | Notes |
|---|---|---|---|
| `rate_limits.five_hour.used_percentage` | **float** | absent | e.g. `23.5` — `utilization * 100`, not rounded |
| `rate_limits.five_hour.resets_at` | number | absent | **Unix epoch seconds** |
| `rate_limits.seven_day.used_percentage` | **float** | absent | Same shape |
| `rate_limits.seven_day.resets_at` | number | absent | Same shape |

`rate_limits` appears only for Claude.ai Pro/Max subscribers, and only after the first API
response of the session. Each window is **independently optional**: `five_hour` present with
`seven_day` absent is a normal payload, not a malformed one. v2.1.80.

These are the only percentage fields in the payload that are floats rather than integers, so
`sl_int` will reject them; `sl_num` is the correct helper.

### 3.10 Editor, agent, and PR state

| Field | Type | Presence | Notes |
|---|---|---|---|
| `vim.mode` | string | absent unless vim mode on | `NORMAL`, `INSERT`, `VISUAL`, or `VISUAL LINE` |
| `agent.name` | string | absent | Present with `--agent` or configured agent settings |
| `pr.number` | number | absent | Open PR for the current branch; the GitLab merge request number when the remote is GitLab. Removed once the PR merges or closes. v2.1.145 |
| `pr.url` | string | absent | Link to the PR or MR |
| `pr.review_state` | string | absent independently | `approved`, `pending`, `changes_requested`, or `draft`. MAY be absent while `pr.number` is present |
| `pr.kind` | string | absent for GitHub | `"mr"` only for a GitLab merge request. Absence means GitHub, which keeps pre-2.1.234 scripts working. v2.1.234+ |

### 3.11 `--worktree` sessions

| Field | Type | Presence | Notes |
|---|---|---|---|
| `worktree.name` | string | absent outside `--worktree` | Active worktree name |
| `worktree.path` | string | absent outside `--worktree` | Absolute path to the worktree |
| `worktree.branch` | string | absent for hook-based worktrees | e.g. `worktree-my-feature` |
| `worktree.original_cwd` | string | absent outside `--worktree` | Directory before entering the worktree |
| `worktree.original_branch` | string | absent for hook-based worktrees | Branch before entering the worktree |

`worktree.*` is **not** the same as `workspace.git_worktree`. `workspace.git_worktree` is set
for any linked worktree the user happens to be inside; `worktree.*` exists only for sessions
Claude Code itself launched with `--worktree`. A segment that wants "am I in a worktree" MUST
read `workspace.git_worktree`; a segment that wants "what did this session branch from" MUST
read `worktree.*`. v2.1.69.

---

## 4. Presence Semantics: Absent, Null, and Zero

Distinguishing these three states is a correctness requirement in this project
(`AGENTS.md` §4.1, `CODING-STANDARDS.md` §4). A missing context window is **unknown**, not
0% used, and rendering it as `0%` is a confidently wrong number — the failure mode this
project's whole error policy exists to prevent.

**Keys that are ABSENT when they do not apply** — the key is not in the JSON at all:

`session_name`, `prompt_id`, `workspace.git_worktree`, `workspace.repo` (whole object),
`effort` (whole object), `vim` (whole object), `agent` (whole object), `pr` (whole object,
and `pr.review_state` / `pr.kind` individually), `worktree` (whole object, and `branch` /
`original_branch` individually), `rate_limits` (whole object, and each window individually).

**Keys that are PRESENT but NULL:**

`context_window.current_usage`, `context_window.used_percentage`,
`context_window.remaining_percentage` — all three null before the first API call and again
immediately after `/compact`, until the next API response repopulates them.

**Guidance:**

- In `jq`, guard with `// empty` when absence should propagate as "no value", and with an
  explicit sentinel when the caller must distinguish absence from a legitimate empty string.
  `lib/core.sh` uses `SL_ABSENT` (`\001`) for exactly this reason, and `sl_has` is the test.
- `// 0` is the wrong default for anything a user reads as a measurement. It is acceptable
  only where zero is genuinely the meaning — for example `cost.total_lines_added` on a session
  that has changed nothing.
- The post-`/compact` null window is the most commonly hit case in practice, because it occurs
  in the middle of an otherwise healthy session. Every fixture set MUST include it.

---

## 5. Caching

Cache files MUST be keyed on **`session_id`**. It is stable for the session's lifetime and
unique across sessions, which is exactly the shape a per-session cache needs. This is also
what the official documentation instructs.

Process identifiers — `$$`, `os.getpid()`, `process.pid` — change on **every invocation**,
because every render is a fresh process. A pid-keyed cache never hits, grows one file per
render, and silently defeats the caching that the latency budget depends on. This is a common
enough mistake that it is called out in the upstream docs.

Cache location: this project writes under `${XDG_CACHE_HOME:-$HOME/.cache}/statuslines/`
(`AGENTS.md` §3.3), created mode `700`. `$XDG_RUNTIME_DIR` is an acceptable alternative where
it exists. A world-writable `/tmp/statusline-...-$SESSION_ID` path — as the upstream example
shows — MUST NOT be used here: on a shared host any user can pre-create or replace that file,
and a status line reading it renders attacker-controlled text into the maintainer's terminal.

Per `AGENTS.md` §4.4, every cache MUST have an explicit documented TTL, and a stale value MUST
be rendered as stale rather than presented as live.

---

## 6. Subagent Status Lines

`subagentStatusLine` renders the body of each subagent row in the agent panel. It is invoked
**once per refresh tick** with all visible rows in a single payload, not once per row.

Input: the base hook fields, a `columns` field carrying the usable row width, and a `tasks`
array. Each task carries `id`, `name`, `type`, `status`, `description`, `label`, `startTime`,
`model`, `effort`, `contextWindowSize`, `tokenCount`, `tokenSamples`, and `cwd`.

- `model` and `contextWindowSize` require v2.1.205+ and are omitted while a task's model is
  unresolved. `contextWindowSize` is computed the same way as the main payload's
  `context_window.context_window_size`, so a per-row percentage from `tokenCount` is
  meaningful.
- `effort` requires v2.1.214+, is either an effort level string or a numeric token budget,
  reports the configured value as written (the model MAY apply something different), and is
  absent when the subagent inherits the session's effort.

Output: one JSON line per row, `{"id": "<task id>", "content": "<row body>"}`. Omitting a
task's id keeps its default rendering; an empty `content` hides the row. ANSI and OSC 8 are
permitted in `content`.

The same trust, `disableAllHooks`, and `allowManagedHooksOnly` gates from §2.6 apply.

---

## 7. Version Timeline

| Version | Field or behavior introduced |
|---|---|
| 1.0.71 | Status line feature introduced |
| 1.0.85 | `cost.*` |
| 1.0.88 | `exceeds_200k_tokens` |
| 2.0.65 | `context_window` object |
| 2.0.70 | `context_window.current_usage` |
| 2.1.6 | `context_window.used_percentage`, `context_window.remaining_percentage` |
| 2.1.47 | `workspace.added_dirs` |
| 2.1.51 | Workspace trust required before the command runs (security fix) |
| 2.1.69 | `worktree.*` |
| 2.1.80 | `rate_limits.*` |
| 2.1.97 | `statusLine.refreshInterval`, `workspace.git_worktree` |
| 2.1.119 | `effort.level`, `thinking.enabled` |
| 2.1.132 | Fix: `context_window` was cumulative, now reflects the current window |
| 2.1.141 | Fix: an over-width line no longer corrupts neighboring rows |
| 2.1.145 | `workspace.repo.*`, `pr.number`, `pr.url`, `pr.review_state` |
| 2.1.153 | `COLUMNS` and `LINES` exported to the command |
| 2.1.196 | `prompt_id` |
| 2.1.205 | Subagent task `model`, `contextWindowSize` |
| 2.1.211 | `/clear` resets `cost.total_cost_usd` to `$0` |
| 2.1.214 | Subagent task `effort` |
| 2.1.234 | GitLab merge request support, `pr.kind` |

**This table is a compatibility reference, not a minimum-version declaration.** This project
supports older Claude Code releases by treating every field as optional with an explicit
default (`AGENTS.md` §4.1), so no segment may require a version. The timeline's use is
diagnostic: when a user reports a segment rendering as unknown, the first question is which
version they run and whether the field existed in it.

---

## 8. Derived Values

The payload does not provide these directly. They are recorded here because they are the
formulas the segments use, and because getting them subtly wrong produces a plausible number
rather than a visible failure.

Every one of these MUST guard its denominator: a brand-new session has
`total_duration_ms` near zero, and division before the first API response is the standard way
this class of segment produces a nonsense value or aborts the render under `set -e`.

| Value | Formula | Guard |
|---|---|---|
| Burn rate ($/h) | `total_cost_usd * 3600000 / total_duration_ms` | `total_duration_ms > 0` |
| Tokens per minute | `tokens * 60000 / duration_ms` | `duration_ms > 0` |
| Cache hit ratio | `cache_read / (input + cache_creation + cache_read)` | denominator `> 0`; render unknown before the first API call |
| API share of wall clock | `total_api_duration_ms / total_duration_ms` | `total_duration_ms > 0`; clamp to 1, since concurrent API calls can push the sum past wall clock |
| Time until reset | `resets_at - now` | `resets_at` is epoch **seconds**, not milliseconds |
| Rate-limit pace | `delta = used_percentage - (elapsed_share * 100)` | see below |

**Rate-limit pace.** `elapsed_share` is the fraction of the window that has already passed:

```
window_minutes    = 300    (five_hour) | 10080 (seven_day)
minutes_remaining = (resets_at - now) / 60
elapsed_share     = (window_minutes - minutes_remaining) / window_minutes
delta             = used_percentage - elapsed_share * 100
```

A positive `delta` means the session is consuming quota faster than the window replenishes it;
zero means exactly on pace. This is the number worth showing, because raw `used_percentage`
early in a window is alarming and meaningless.

**Epoch units.** `resets_at` is in **seconds**. Comparing it against a millisecond clock —
`Date.now()`, `date +%s%3N` — yields a reset date in 1970 or a countdown of ~55 years. This is
the single most common bug in rate-limit segments.

**Determinism.** `CODING-STANDARDS.md` §5.3 forbids wall-clock reads inside rendering logic.
Any segment needing `now` MUST accept it as an injectable parameter so golden tests can pin
it; otherwise its output is untestable.

**Compaction-aware context (optional).** Measuring against `context_window_size - 33000`
rather than the full window reports distance to auto-compaction rather than raw window
occupancy, which is closer to what a user actually wants to know — the question is usually
"how long until my context gets rewritten", not "how full is the buffer".

```
compaction_pct = round(used_tokens / (context_window_size - 33000) * 100)
```

A theme MAY adopt this, and MUST label it distinctly from `used_percentage` so the two are not
mistaken for the same measurement. The **33k buffer is an observed value, not a documented
guarantee**: it is not in the payload, it is not in the official documentation, and Claude
Code MAY change it in any release. A theme depending on it MUST degrade to plain
`used_percentage` rather than to a wrong number if the assumption stops holding.

---

## 9. Fields Not To Depend On

### 9.1 Undocumented but actually emitted (verified in 2.1.234)

| Field | Notes |
|---|---|
| `agent_type` | Top level. Set from the same source as `agent.name`; present whenever an agent name exists |
| `remote.session_id` | Present when a remote-control session is active |

These are real in the payload and absent from the documentation, which means they carry no
compatibility promise and MAY be renamed or removed without a note in the changelog. A shipped
segment MUST NOT depend on either. Recording them here is what stops someone from
rediscovering them and assuming they are supported.

### 9.2 Not emitted, despite appearing elsewhere

| Field | Why it is missing |
|---|---|
| `hook_event_name` | Sent to hooks, **not** to `statusLine`. A script keying on it will never match, and a copied hook script will silently render nothing |
| `permission_mode` | Exists in the shared base-fields helper, but is passed `undefined` on the statusline path and dropped from the serialized JSON |
| `agent_id` | Same as `permission_mode`: present in the helper, undefined here, dropped |

`permission_mode` is worth calling out separately: a permission-mode change is one of the
triggers that **re-runs** the status line (§2.1), so a script is invoked precisely when the
mode changes and still cannot read what the mode now is.

---

## Version History

| Date | Version | Change |
|------|---------|--------|
| 2026-08-17 | 1.0.0 | Initial contract, verified against Claude Code 2.1.234 |
