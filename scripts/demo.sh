#!/usr/bin/env bash
# Render every theme against every fixture, to a real terminal.
#
# `make test` compares bytes; this exists because bytes do not tell you whether
# a line is legible. AGENTS.md §6.2 requires a human to actually look.
set -euo pipefail

SL_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export SL_REPO
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib-test-env.sh
. "${SL_REPO}/scripts/lib-test-env.sh"

only_theme=${1-}

for fixture in "${SL_REPO}"/test/fixtures/*.json; do
  base=${fixture##*/}
  printf '\n\033[1m=== %s ===\033[0m\n' "${base%.json}"
  for theme in $SL_TEST_THEMES; do
    [ -n "$only_theme" ] && [ "$theme" != "$only_theme" ] && continue
    printf '\033[2m%-10s\033[0m ' "$theme"
    sl_test_render "$fixture" "$theme"
    printf '\n'
  done
done
