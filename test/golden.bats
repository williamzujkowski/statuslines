#!/usr/bin/env bats
# Golden-file tests: rendering is a deterministic function of (fixture, theme),
# which is what makes byte comparison the right mechanism here.

setup() {
  SL_REPO=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
  export SL_REPO
  # shellcheck source=../scripts/lib-test-env.sh
  . "${SL_REPO}/scripts/lib-test-env.sh"
}

@test "every fixture has a golden file for every theme" {
  local missing=0
  for fixture in "${SL_REPO}"/test/fixtures/*.json; do
    local base=${fixture##*/}; base=${base%.json}
    for theme in $SL_TEST_THEMES; do
      if [ ! -f "${SL_REPO}/test/golden/${base}.${theme}.txt" ]; then
        echo "missing golden: ${base}.${theme}.txt"
        missing=$((missing + 1))
      fi
    done
  done
  [ "$missing" -eq 0 ]
}

@test "rendered output matches every golden file" {
  local failures=0
  for fixture in "${SL_REPO}"/test/fixtures/*.json; do
    local base=${fixture##*/}; base=${base%.json}
    for theme in $SL_TEST_THEMES; do
      local golden="${SL_REPO}/test/golden/${base}.${theme}.txt"
      [ -f "$golden" ] || continue
      local actual expected
      actual=$(sl_test_render "$fixture" "$theme")
      expected=$(cat "$golden")
      if [ "$actual" != "$expected" ]; then
        echo "--- MISMATCH ${base} / ${theme}"
        echo "expected: $(printf '%q' "$expected")"
        echo "actual:   $(printf '%q' "$actual")"
        failures=$((failures + 1))
      fi
    done
  done
  [ "$failures" -eq 0 ]
}

@test "rendering is idempotent" {
  local first second
  first=$(sl_test_render "${SL_REPO}/test/fixtures/full.json" dashboard)
  second=$(sl_test_render "${SL_REPO}/test/fixtures/full.json" dashboard)
  [ "$first" = "$second" ]
}

@test "the single-file bundle renders identically to the repository build" {
  # A bundle that has drifted from the sources is worse than no bundle: it is
  # what users actually install, so it is the thing that has to be right.
  local out="${BATS_TEST_TMPDIR}/statusline.sh"
  run bash "${SL_REPO}/scripts/bundle.sh" "$out"
  [ "$status" -eq 0 ]

  local fixture theme bundled repo
  for fixture in "${SL_REPO}"/test/fixtures/*.json; do
    for theme in $SL_TEST_THEMES; do
      bundled=$(COLUMNS="$SL_TEST_COLUMNS" SL_NOW="$SL_TEST_NOW" \
        STATUSLINE_THEME="$theme" HOME=/home/user \
        "${BASH_BIN:-bash}" "$out" <"$fixture" 2>/dev/null)
      repo=$(sl_test_render "$fixture" "$theme")
      if [ "$bundled" != "$repo" ]; then
        echo "bundle drift: ${fixture##*/} / ${theme}"
        echo "repo:   $(printf '%q' "$repo")"
        echo "bundle: $(printf '%q' "$bundled")"
        return 1
      fi
    done
  done
}
