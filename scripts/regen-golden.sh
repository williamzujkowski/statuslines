#!/usr/bin/env bash
# Regenerate every golden file.
#
# Deliberately a separate command from `make test`: goldens are only ever
# updated on purpose, and the resulting diff must be reviewed in the pull
# request (docs/CODING-STANDARDS.md §5.2). Auto-accepting a golden diff defeats
# the entire mechanism.
set -euo pipefail

SL_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export SL_REPO
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib-test-env.sh
. "${SL_REPO}/scripts/lib-test-env.sh"

mkdir -p "${SL_REPO}/test/golden"
count=0

for fixture in "${SL_REPO}"/test/fixtures/*.json; do
  base=${fixture##*/}
  base=${base%.json}
  for theme in $SL_TEST_THEMES; do
    out="${SL_REPO}/test/golden/${base}.${theme}.txt"
    sl_test_render "$fixture" "$theme" >"$out"
    count=$((count + 1))
  done
done

printf 'Regenerated %d golden files.\n' "$count"
printf 'Review the diff before committing:  git diff test/golden/\n'
