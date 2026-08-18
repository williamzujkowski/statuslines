#!/usr/bin/env bash
# Shared, pinned environment for anything that renders for comparison.
#
# Every value here is fixed so that output is a pure function of the fixture
# and the theme (docs/CODING-STANDARDS.md §5.3). An unpinned COLUMNS or clock
# makes golden files machine-specific, which makes them worthless.
SL_TEST_COLUMNS=120
SL_TEST_NOW=1755490000
# shellcheck disable=SC2034 # consumed by the scripts and bats files that source this
SL_TEST_THEMES="default minimal plain dashboard powerline"

# sl_test_render <fixture> <theme>
sl_test_render() {
  local fixture=$1 theme=$2
  COLUMNS="$SL_TEST_COLUMNS" \
    SL_NOW="$SL_TEST_NOW" \
    STATUSLINE_THEME="$theme" \
    NO_COLOR='' \
    STATUSLINE_COLOR='' \
    HOME=/home/user \
    "${BASH_BIN:-bash}" "${SL_REPO}/statusline.sh" <"$fixture" 2>/dev/null
}
