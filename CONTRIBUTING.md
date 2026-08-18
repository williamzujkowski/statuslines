# Contributing

Thanks for looking. This is a small Bash project with an unusually specific set of constraints,
and most of them exist because a status line runs on every keystroke-adjacent event in someone's
terminal. This document is the practical path through them.

Two documents are binding and this one does not restate them in full:

- [`AGENTS.md`](AGENTS.md) — the behavioral contract. Written for AI coding agents, but it is
  where the project's rules actually live, and it takes precedence over everything here.
- [`docs/CODING-STANDARDS.md`](docs/CODING-STANDARDS.md) — the craft detail behind it: change
  safety, simplicity limits, module boundaries, accessibility.

Read [`docs/STATUSLINE-CONTRACT.md`](docs/STATUSLINE-CONTRACT.md) before you touch anything that
reads the payload, and [`docs/THEMES.md`](docs/THEMES.md) before you touch anything a theme
configures.

---

## Bootstrap and verify

Two commands. Both must work from a fresh clone; if either is broken, fixing it takes priority
over whatever you came to do.

```sh
make setup   # install dev tooling, report what's missing, install the commit-msg hook
make check   # lint, format check, tests, benchmark — this is the gate
```

`make setup` checks for the runtime dependencies (`bash`, `jq`, `git`) and the development ones
(`shellcheck`, `shfmt`, `bats`), prints install commands for whatever is missing, and installs
`scripts/commit-msg` into `.git/hooks/`. That hook is pure bash — it deliberately does not require
node or an npm install.

Other targets:

| Target | What it does |
|---|---|
| `make lint` | `shellcheck --severity=style` over every shell file |
| `make fmt` | `shfmt -w -i 2 -ci -bn` in place |
| `make fmt-check` | the same, as a diff, without writing |
| `make test` | the `bats` suite |
| `make bench` | render latency against the budget |
| `make demo` | render every theme against every fixture, to a real terminal |
| `make golden` | regenerate golden files — review the diff before committing |

`make golden` is not a way to make a failing test pass. Regenerating a golden file is a claim that
the new output is correct, and the PR has to say in words why it is.

## Commits and PR titles

This repository uses [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) and
[release-please](https://github.com/googleapis/release-please), which means commit messages are a
correctness concern rather than a style preference: the changelog and the version bump are derived
from them.

```
<type>(<optional scope>): <description>
```

**Types:** `feat` `fix` `perf` `refactor` `docs` `test` `build` `ci` `chore` `style` `revert`

**Scopes:** `core` `render` `segments` `themes` `config` `install` `test` `docs` `ci` `bench`
`deps` — or a segment name where the change is local to one, e.g. `segments/git`.

Rules: imperative mood, lowercase description, no trailing period, header at most 100 characters.
Use `feat:` only for a user-visible capability and `fix:` only for a user-visible defect; internal
cleanups are `refactor:` or `chore:` and must not inflate the changelog. Breaking changes take a
`!` after the type and a `BREAKING CHANGE:` footer — for this project that means a removed or
renamed theme key, a changed segment interface, a moved install path, or a new required dependency.

```
feat(segments): add usage-block burn rate segment
fix(render): stop truncating multibyte branch names mid-character
feat(themes)!: rename `separator` key to `divider`
```

### The PR title is what CI validates

`main` is **squash-merged**, so the PR title becomes the commit subject on `main`, and that subject
is what release-please reads to decide the version bump and write the changelog entry. CI therefore
lints the **pull request title**, not the individual commits, with a SHA-pinned
`amannn/action-semantic-pull-request` step.

The practical consequence: a tidy branch history with a sloppy PR title still produces a wrong
changelog. Get the title right.

The local `commit-msg` hook checks the same shape on each commit so you find out early. Do not
bypass it with `--no-verify`.

### Generated files

`CHANGELOG.md` and `version.txt` are owned by release-please. Do not hand-edit either, and do not
hand-write a changelog entry or bump a version number — it will be overwritten at the next release.
If a changelog entry is wrong, the commit message was wrong; fix that instead.

## Pull request checklist

Every PR needs all five sections of [`.github/pull_request_template.md`](.github/pull_request_template.md)
— Context, Change, Verification, Rollback, Compatibility — plus these boxes:

- [ ] Conventional Commit messages (`make setup` installs the hook)
- [ ] New/changed segments are wired: registry + a theme + `docs/THEMES.md`
- [ ] Fixtures and golden files added or updated, and the diff was reviewed
- [ ] `CHANGELOG.md` and `version.txt` untouched (release-please owns them)

Verification means real command output. "Tests should pass" is not a test result. If you did not
run the terminal check, say the terminal check was not run.

## Adding a segment

A segment is one file, `lib/segments/<name>.sh`, exporting exactly one function:

```bash
#!/usr/bin/env bash
# thing — one line saying what this shows and where it comes from.
segment_thing() {
  sl_has some_field || return 1
  sl_paint "$(sl_theme_get thing_color cyan)" "$(sl_get some_field)"
}
```

The contract:

- **Exactly one exported function, named `segment_<name>`.** The renderer sources the file lazily
  and dispatches by name; anything else in the file should be a `_sl_`-prefixed helper.
- **Write the fragment to stdout. Return `1` for "nothing to show."** Not an empty string and
  not an error — non-zero is the normal, expected way to say the payload has nothing here.
- **Return greater than `1` only when the segment genuinely failed.** `1` means "the data was not
  there", which is ordinary; anything higher means "I am broken", and the renderer prints a visible
  marker in the slot instead of leaving it silently empty. Do not return `2` for absent data — every
  quiet segment would look broken.
- **Know nothing about layout.** No separators, no other segments, no terminal width. That
  ignorance is what lets someone add a segment without reading `lib/render.sh`.
- **Read the payload only through the `sl_*` helpers.** `sl_has`, `sl_get`, `sl_int`, `sl_num`,
  `sl_bool`, `sl_numeric`, `sl_now`. `lib/core.sh` is the only file that runs `jq`; a segment that
  re-parses JSON is both a spawn and a boundary violation.
- **Emit color only through `lib/colors.sh`.** `sl_paint`, `sl_threshold_color`. No file other than
  `lib/colors.sh` may contain an escape literal.
- **Distinguish unknown from zero.** `sl_int field 0` is right when zero is genuinely the meaning
  (`lines_added` on a session that changed nothing) and wrong when the field is simply absent.
  `sl_numeric` exists for the display case: a value you are going to show must be gated on it, so
  a wrong-typed or missing field renders as `--` rather than as `0%`.
- **Take `now` as `sl_now`.** It honors `SL_NOW`, which is how golden tests pin anything
  time-dependent. A segment calling `date` directly is untestable.

Then wire it, all four steps. **A segment that exists but is not referenced by a theme is inert,
and shipping it is a silent failure** — it will pass every test you wrote and never appear in
anyone's terminal.

1. Create `lib/segments/<name>.sh`.
2. Reference it from at least one theme's `line1`..`line9`.
3. Document it in `docs/THEMES.md` — the segment table and every theme key it reads, with defaults.
4. Add a fixture and a golden file.

## Adding a theme

A theme is a `key = value` file in `themes/`. Themes are **parsed, never sourced**: a theme is a
file people copy off the internet, and sourcing one would make "install this theme" mean "run this
code". Keep it declarative — no command substitution, no shell syntax, nothing that would only work
if it were sourced.

Requirements for a shipped theme:

- Declare `name`, `description`, and `requires`. `requires = none` unless it genuinely needs
  something; `requires = nerdfont` if it uses glyphs a stock font lacks.
- Quote any value whose leading or trailing spaces matter. Unquoted values are trimmed, which
  silently glues every segment together if `separator` is unquoted.
- Use only the 16 standard SGR color names. The terminal's own theme maps those to something the
  user can read; a hardcoded 256-color value can land invisibly close to their background.
- Stay readable with color stripped. Run it under `NO_COLOR=1` and check that no value was carried
  by color alone.
- Ship a `drop_order` and a `width_reserve`, and check it at `COLUMNS=80` and `COLUMNS=40`.
- Add a golden file for it against the existing fixtures, and a row in `docs/THEMES.md`.

Per `docs/CODING-STANDARDS.md` §6.2, a configuration option must not ship without a theme that
uses it. If no shipped theme exercises a new key, the key is speculative surface area and does not
ship.

## Shell rules

The floor is **bash 3.2**, because stock macOS ships 3.2.57 and always will. CI has a dedicated job
that asserts `/bin/bash` really is 3.2 and runs the suite under it, so this is enforced rather than
aspirational.

- No bash 4+ constructs: no associative arrays, no `${var,,}` / `${var^^}`, no `mapfile` /
  `readarray`, no `**` globstar, no `&>>`.
- Quote every expansion, including inside `[[ ]]` where habit says it is safe. Directory names
  contain spaces and branch names contain `$`.
- `printf` rather than `echo` for anything with a variable or an escape in it — and never
  `printf "$value"` with payload data in the format position.
- Prefer builtins and parameter expansion over spawning `sed`, `awk`, `cut`, or `bc`. Every spawn
  is about a millisecond of the budget. `sl_seq` and `sl_strip_ansi` exist for exactly this reason.
- `shellcheck` clean at `--severity=style` with no suppressions. A genuinely necessary suppression
  needs an inline comment on the line above explaining why.
- `shfmt -i 2 -ci -bn`. Run `make fmt`.
- Only `lib/colors.sh` may contain an escape literal.
- Functions ≤50 lines, files ≤400 lines, nesting ≤3, function parameters ≤5. Exceeding a limit is
  allowed with written justification in the PR; silence is not.

Note that `statusline.sh` runs under `set -uo pipefail` and deliberately **not** `set -e`: segments
return non-zero routinely to mean "nothing to show", and under `set -e` that would abort the render
and leave a blank line. Errors are handled explicitly at each call site instead. Library scripts
that are not the render path (`scripts/*.sh`) do use `set -euo pipefail`.

## Latency

| Measurement | Target | Ceiling |
|---|---|---|
| Full render, warm | < 100 ms | 300 ms |
| Any single segment | < 15 ms | 50 ms |
| Process spawns per render | ≤ 4 | 8 |

This is a correctness rule, not a nicety. Claude Code debounces renders by 300 ms and *aborts* an
in-flight run when a new trigger arrives, discarding whatever was already written. A slow status
line does not render late — during an active turn it renders nothing, with no error anywhere.

**Any PR touching the render path must include before/after benchmark numbers**, measured with
`make bench`, in the table in the PR template. Measured, not estimated. A change that increases p95
has to justify itself against the feature gained or be rejected. A segment that cannot meet its
budget belongs behind a cache with a documented TTL, and a stale cached value must be rendered as
stale rather than presented as live.

## Security expectations

The status line has exactly one trust boundary: the JSON payload on stdin. Directory paths, branch
names, model names, and agent names all originate outside this code, and a repository someone else
authored can name a branch whatever it likes.

- **The payload is untrusted.** Validate at the boundary, once, in `lib/core.sh`. Control
  characters are stripped there so a branch name cannot smuggle an `ESC` into the line and repaint
  someone's terminal. Downstream segments consume already-scrubbed values.
- **No `eval`, ever.** No interpolating a payload value into a command string, a filename, or a
  variable name. Anything that selects behavior — a theme name, a segment name, a color token —
  goes through an allowlist before it reaches a path or a `printf -v`.
- **No network calls at render time.** None. This is offline code.
- **No writes outside `${XDG_CACHE_HOME:-$HOME/.cache}/statuslines/`.** A status line is an
  observer, not an actor. It must not mutate the repository it is describing.
- **Never spawn a `git` command that could take a lock.** Renders happen mid-edit; lock contention
  hangs the user's terminal. The `git` segment reads `.git/HEAD` off the filesystem for this
  reason.
- **Scrub fixtures before committing them.** Replace real home directories with `/home/user` or
  `/Users/user`, real session UUIDs with a fixed dummy, real project names with neutral ones, and
  drop `transcript_path` values that reveal a directory layout. Fixtures are public and git history
  is permanent — a scrub after the fact needs a history rewrite, not a follow-up commit.

If you find a way this code could harm a user's terminal, shell, or repository, please report it
privately to the maintainer rather than opening a public issue describing it before a fix exists.

## Filing issues

Every identified piece of work becomes a GitHub issue, including work being deliberately deferred.
Deferring is fine; untracked is not. A `TODO` comment or a "follow-up" bullet in a PR description
is not tracking.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
