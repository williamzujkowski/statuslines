#!/usr/bin/env bats
# Properties that must hold for ANY input, not just the fixtures. These are the
# invariants named in docs/CODING-STANDARDS.md §5.4.

setup() {
  SL_REPO=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
  export SL_REPO
  # shellcheck source=../scripts/lib-test-env.sh
  . "${SL_REPO}/scripts/lib-test-env.sh"
  SL="${SL_REPO}/statusline.sh"
}

render_raw() {
  COLUMNS=120 SL_NOW=1755490000 STATUSLINE_THEME="${2:-default}" \
    "${BASH_BIN:-bash}" "$SL" <<<"$1" 2>/dev/null
}

@test "always exits 0, whatever the input" {
  local inputs=(
    ''
    'not json'
    '{'
    '[]'
    'null'
    'true'
    '{"workspace":123}'
    '{"cost":[]}'
    '0000'
  )
  for input in "${inputs[@]}"; do
    run render_raw "$input"
    [ "$status" -eq 0 ] || { echo "non-zero exit for input: $input"; return 1; }
  done
}

@test "never emits nothing: even garbage produces a visible line" {
  run render_raw 'not json at all'
  [ -n "$output" ]
  [[ "$output" == *degraded* ]]
}

@test "a degraded render says so rather than showing a plausible line" {
  run render_raw ''
  [[ "$output" == *degraded* ]]
  # It must not invent values it does not have.
  [[ "$output" != *'0%'* ]]
  [[ "$output" != *'$0'* ]]
}

@test "no payload-derived escape sequence reaches stdout" {
  # Strip the SGR sequences the theme is entitled to emit; anything left is a
  # leak from the payload.
  for theme in $SL_TEST_THEMES; do
    local out stripped
    out=$(sl_test_render "${SL_REPO}/test/fixtures/hostile-strings.json" "$theme")
    stripped=${out//$'\033['[0-9;]m/}
    stripped=${stripped//$'\033['[0-9;][0-9;]m/}
    case "$stripped" in
      *$'\033'*) echo "escape leaked in theme $theme"; return 1 ;;
      *$'\007'*) echo "BEL leaked in theme $theme"; return 1 ;;
      *$'\r'*) echo "CR leaked in theme $theme"; return 1 ;;
    esac
  done
}

@test "output never exceeds the declared terminal width" {
  for fixture in "${SL_REPO}"/test/fixtures/*.json; do
    for theme in $SL_TEST_THEMES; do
      local out line plain width
      out=$(COLUMNS=80 SL_NOW=1755490000 STATUSLINE_THEME="$theme" HOME=/home/user \
        "${BASH_BIN:-bash}" "$SL" <"$fixture" 2>/dev/null)
      while IFS= read -r line; do
        plain=${line//$'\033['[0-9;]m/}
        plain=${plain//$'\033['[0-9;][0-9;]m/}
        # Strip any remaining SGR forms.
        while [[ "$plain" == *$'\033['*m* ]]; do
          plain="${plain%%$'\033['*}${plain#*m}"
        done
        width=${#plain}
        if [ "$width" -gt 80 ]; then
          echo "line too wide (${width} > 80): ${fixture##*/} / ${theme}"
          echo "line: $plain"
          return 1
        fi
      done <<<"$out"
    done
  done
}

@test "the plain theme emits no escape sequences at all" {
  for fixture in "${SL_REPO}"/test/fixtures/*.json; do
    local out
    out=$(sl_test_render "$fixture" plain)
    case "$out" in
      *$'\033'*) echo "plain theme emitted an escape for ${fixture##*/}"; return 1 ;;
    esac
  done
}

@test "NO_COLOR suppresses color in every theme" {
  for theme in $SL_TEST_THEMES; do
    local out
    out=$(COLUMNS=120 SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME="$theme" HOME=/home/user \
      "${BASH_BIN:-bash}" "$SL" <"${SL_REPO}/test/fixtures/full.json" 2>/dev/null)
    case "$out" in
      *$'\033'*) echo "NO_COLOR ignored by theme $theme"; return 1 ;;
    esac
  done
}

@test "removing any single top-level field never breaks the render" {
  local keys
  keys=$(jq -r 'keys[]' "${SL_REPO}/test/fixtures/full.json")
  while IFS= read -r key; do
    local payload out
    payload=$(jq --arg k "$key" 'del(.[$k])' "${SL_REPO}/test/fixtures/full.json")
    out=$(COLUMNS=120 SL_NOW=1755490000 STATUSLINE_THEME=dashboard HOME=/home/user \
      "${BASH_BIN:-bash}" "$SL" <<<"$payload" 2>/dev/null)
    [ -n "$out" ] || { echo "empty output after deleting .$key"; return 1; }
  done <<<"$keys"
}

@test "a null in place of any top-level object never breaks the render" {
  local keys
  keys=$(jq -r 'to_entries[] | select(.value | type == "object") | .key' \
    "${SL_REPO}/test/fixtures/full.json")
  while IFS= read -r key; do
    local payload out
    payload=$(jq --arg k "$key" '.[$k] = null' "${SL_REPO}/test/fixtures/full.json")
    out=$(COLUMNS=120 SL_NOW=1755490000 STATUSLINE_THEME=dashboard HOME=/home/user \
      "${BASH_BIN:-bash}" "$SL" <<<"$payload" 2>/dev/null)
    [ -n "$out" ] || { echo "empty output after nulling .$key"; return 1; }
  done <<<"$keys"
}

@test "an unknown theme falls back to default instead of failing" {
  run render_raw '{"workspace":{"current_dir":"/home/user/x"},"model":{"display_name":"Opus"}}' 'no-such-theme'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "a theme name cannot escape the themes directory" {
  run render_raw '{"model":{"display_name":"Opus"}}' '../../../etc/passwd'
  [ "$status" -eq 0 ]
  [[ "$output" != *root:* ]]
}

@test "regression: a hostile .git/HEAD cannot inject escapes into the line" {
  # A branch name is read straight off the filesystem, so it never passes
  # through the jq sanitizer. Before lib/core.sh grew sl_scrub, this rendered
  # raw ANSI escapes even under NO_COLOR, letting any repository the user
  # merely opened repaint their terminal.
  local repo="${BATS_TEST_TMPDIR}/evil"
  mkdir -p "${repo}/.git"
  printf 'ref: refs/heads/fix/\033[31mRED\033[0m\007bell\n' >"${repo}/.git/HEAD"

  local payload out
  payload=$(jq -nc --arg d "$repo" '{workspace:{current_dir:$d},model:{display_name:"Opus"}}')

  for theme in $SL_TEST_THEMES; do
    out=$(COLUMNS=140 SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME="$theme" \
      "${BASH_BIN:-bash}" "$SL" <<<"$payload" 2>/dev/null)
    case "$out" in
      *$'\033'*) echo "ESC leaked from .git/HEAD in theme $theme"; return 1 ;;
      *$'\007'*) echo "BEL leaked from .git/HEAD in theme $theme"; return 1 ;;
    esac
    # The branch should still be shown, just declawed.
    [[ "$out" == *"fix/"* ]] || { echo "branch vanished entirely in theme $theme"; return 1; }
  done
}

@test "a very long branch name is bounded, not left to blow out the line" {
  local repo="${BATS_TEST_TMPDIR}/longbranch"
  mkdir -p "${repo}/.git"
  printf 'ref: refs/heads/%s\n' "$(printf 'x%.0s' $(seq 1 300))" >"${repo}/.git/HEAD"

  local payload out
  payload=$(jq -nc --arg d "$repo" '{workspace:{current_dir:$d},model:{display_name:"Opus"}}')
  out=$(COLUMNS=200 SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME=plain \
    "${BASH_BIN:-bash}" "$SL" <<<"$payload" 2>/dev/null)
  [ "${#out}" -lt 200 ]
}

@test "a broken segment renders a visible marker, not silence" {
  # Regression for #35. A segment that crashes previously vanished, which made
  # it indistinguishable from one that simply had nothing to show — degraded
  # state presented as healthy, which AGENTS.md §7.3 forbids.
  local seg="${SL_REPO}/lib/segments/zzbroken.sh"
  printf 'segment_zzbroken() { ((( }\n' >"$seg"
  # shellcheck disable=SC2064
  trap "rm -f '$seg'" RETURN

  local theme="${BATS_TEST_TMPDIR}/statuslines/themes/brk.conf"
  mkdir -p "${BATS_TEST_TMPDIR}/statuslines/themes"
  printf 'name = brk\nline1 = dir zzbroken\nseparator = " | "\ncolor = off\n' >"$theme"

  local out
  out=$(COLUMNS=140 SL_NOW=1755490000 STATUSLINE_THEME=brk \
    XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}" \
    "${BASH_BIN:-bash}" "$SL" <"${SL_REPO}/test/fixtures/minimal.json" 2>/dev/null)

  [[ "$out" == *"?zzbroken"* ]] || { echo "no marker for a broken segment: $out"; return 1; }
}

@test "a theme naming a segment that does not exist says so" {
  local theme="${BATS_TEST_TMPDIR}/statuslines/themes/miss.conf"
  mkdir -p "${BATS_TEST_TMPDIR}/statuslines/themes"
  printf 'name = miss\nline1 = dir nosuchsegment\nseparator = " | "\ncolor = off\n' >"$theme"

  local out
  out=$(COLUMNS=140 SL_NOW=1755490000 STATUSLINE_THEME=miss \
    XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}" \
    "${BASH_BIN:-bash}" "$SL" <"${SL_REPO}/test/fixtures/minimal.json" 2>/dev/null)

  [[ "$out" == *"?nosuchsegment"* ]] || { echo "no marker for a missing segment: $out"; return 1; }
}

@test "a segment with nothing to show stays silent and gets no marker" {
  # The other half of the contract: absent data is normal, not an error. A
  # marker here would make every quiet segment look broken.
  local out
  out=$(COLUMNS=140 SL_NOW=1755490000 STATUSLINE_THEME=plain \
    "${BASH_BIN:-bash}" "$SL" <"${SL_REPO}/test/fixtures/minimal.json" 2>/dev/null)

  case "$out" in
    *"?"*) echo "a quiet segment was marked as broken: $out"; return 1 ;;
  esac
  [ -n "$out" ]
}

@test "regression: a theme file cannot inject escape sequences" {
  # Two routes, both closed: a control character in an ordinary theme value
  # (pre-existing, e.g. a screen-clearing separator), and one in a segment
  # NAME, which only became reachable once unknown segments started rendering
  # a marker. A theme is data and must never be able to drive the terminal.
  local themedir="${BATS_TEST_TMPDIR}/statuslines/themes"
  mkdir -p "$themedir"
  printf 'name = evil\nline1 = dir \033[31mPWNED\033[0m model\nseparator = "\033[2J\033[H"\ncontext_label = \033[5mB\ncolor = off\n' \
    >"$themedir/evil.conf"

  local out
  out=$(COLUMNS=140 SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME=evil \
    XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}" \
    "${BASH_BIN:-bash}" "$SL" <"${SL_REPO}/test/fixtures/full.json" 2>/dev/null)

  case "$out" in
    *$'\033'*) echo "theme injected an escape: $(printf '%q' "$out")"; return 1 ;;
  esac
  [ -n "$out" ]
}
