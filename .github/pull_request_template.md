<!-- AGENTS.md §7.2 — all five sections are required. -->

## Context
<!-- What problem is this solving, and why does it matter? -->

## Change
<!-- What was modified. Map it to the plan if one was approved. -->

## Verification
<!-- Real command output. Not "tests should pass". -->

```
$ make check
```

<!-- Render-path changes MUST include before/after benchmark numbers: -->
| | p50 | p95 | spawns |
|---|---|---|---|
| before | | | |
| after  | | | |

## Rollback
<!-- How to revert this. -->

## Compatibility
<!-- Did the theme format, a config key, or the install path change?
     What must existing users do? Breaking changes need `!` + BREAKING CHANGE:. -->

- [ ] Conventional Commit messages (`make setup` installs the hook)
- [ ] New/changed segments are wired: registry + a theme + `docs/THEMES.md`
- [ ] Fixtures and golden files added or updated, and the diff was reviewed
- [ ] `CHANGELOG.md` and `version.txt` untouched (release-please owns them)
