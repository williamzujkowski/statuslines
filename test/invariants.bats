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
  # Planted in the test's own segment directory, not the live repository tree:
  # a RETURN trap does not survive an interrupted run, and it races a parallel
  # bats invocation.
  local segdir="${BATS_TEST_TMPDIR}/statuslines/segments"
  mkdir -p "$segdir"
  printf 'segment_zzbroken() { ((( }\n' >"$segdir/zzbroken.sh"

  local theme="${BATS_TEST_TMPDIR}/statuslines/themes/brk.conf"
  mkdir -p "${BATS_TEST_TMPDIR}/statuslines/themes"
  printf 'name = brk\nline1 = dir zzbroken\nseparator = " | "\ncolor = off\n' >"$theme"

  local out
  out=$(COLUMNS=140 SL_NOW=1755490000 STATUSLINE_THEME=brk \
    HOME="${BATS_TEST_TMPDIR}/home" \
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
    HOME="${BATS_TEST_TMPDIR}/home" \
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
    HOME="${BATS_TEST_TMPDIR}/home" \
    XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}" \
    "${BASH_BIN:-bash}" "$SL" <"${SL_REPO}/test/fixtures/full.json" 2>/dev/null)

  case "$out" in
    *$'\033'*) echo "theme injected an escape: $(printf '%q' "$out")"; return 1 ;;
  esac
  [ -n "$out" ]
}

@test "a user segment directory is searched before the shipped one" {
  local segdir="${BATS_TEST_TMPDIR}/statuslines/segments"
  mkdir -p "$segdir"
  printf 'segment_zzuser() { sl_paint green "from-user-dir"; }\n' >"$segdir/zzuser.sh"

  local themedir="${BATS_TEST_TMPDIR}/statuslines/themes"
  mkdir -p "$themedir"
  printf 'name = u\nline1 = dir zzuser\nseparator = " | "\ncolor = off\n' >"$themedir/u.conf"

  local out
  out=$(COLUMNS=140 SL_NOW=1755490000 STATUSLINE_THEME=u \
    HOME="${BATS_TEST_TMPDIR}/home" \
    XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}" \
    "${BASH_BIN:-bash}" "$SL" <"${SL_REPO}/test/fixtures/minimal.json" 2>/dev/null)

  [[ "$out" == *"from-user-dir"* ]] || { echo "user segment not loaded: $out"; return 1; }
}

@test "a user segment shadows a shipped segment of the same name" {
  local segdir="${BATS_TEST_TMPDIR}/statuslines/segments"
  mkdir -p "$segdir"
  printf 'segment_cost() { sl_paint green "SHADOWED"; }\n' >"$segdir/cost.sh"

  local out
  out=$(COLUMNS=140 SL_NOW=1755490000 STATUSLINE_THEME=plain \
    HOME="${BATS_TEST_TMPDIR}/home" \
    XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}" \
    "${BASH_BIN:-bash}" "$SL" <"${SL_REPO}/test/fixtures/full.json" 2>/dev/null)

  [[ "$out" == *"SHADOWED"* ]] || { echo "shipped segment was not shadowed: $out"; return 1; }
  [[ "$out" != *'$3.42'* ]] || { echo "shipped cost segment still rendered: $out"; return 1; }
}

@test "a user segment cannot be reached by a traversing name" {
  local themedir="${BATS_TEST_TMPDIR}/statuslines/themes"
  mkdir -p "$themedir"
  # The theme is data, so it can say anything; the segment loader is what has
  # to refuse. A name with a slash or a dot must never become a path.
  printf 'name = t\nline1 = dir ../../../etc/passwd\nseparator = " | "\ncolor = off\n' >"$themedir/t.conf"

  local out status
  out=$(COLUMNS=140 SL_NOW=1755490000 STATUSLINE_THEME=t \
    HOME="${BATS_TEST_TMPDIR}/home" \
    XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}" \
    "${BASH_BIN:-bash}" "$SL" <"${SL_REPO}/test/fixtures/minimal.json" 2>/dev/null)
  status=$?

  [ "$status" -eq 0 ]
  [[ "$out" != *root:* ]]
}

@test "a segment that prints then returns 1 shows nothing" {
  # Adversarial review finding. `return 1` means "nothing to show" even when the
  # segment already printed something, because it has not decided to show that
  # fragment. Rendering it anyway both contradicts the documented convention and
  # silently changes behaviour from the previous `out=$(...) || out=""`, which
  # discarded output on any non-zero return.
  local segdir="${BATS_TEST_TMPDIR}/statuslines/segments"
  mkdir -p "$segdir"
  printf "segment_zzpartial() { printf 'PARTIAL'; return 1; }\n" >"$segdir/zzpartial.sh"

  local themedir="${BATS_TEST_TMPDIR}/statuslines/themes"
  mkdir -p "$themedir"
  printf 'name = p\nline1 = dir zzpartial\nseparator = " | "\ncolor = off\n' >"$themedir/p.conf"

  local out
  out=$(COLUMNS=140 SL_NOW=1755490000 STATUSLINE_THEME=p \
    HOME="${BATS_TEST_TMPDIR}/home" \
    XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}" \
    "${BASH_BIN:-bash}" "$SL" <"${SL_REPO}/test/fixtures/minimal.json" 2>/dev/null)

  [[ "$out" != *PARTIAL* ]] || { echo "abandoned fragment was rendered: $out"; return 1; }
  # It is empty, not broken — no marker either.
  [[ "$out" != *"?zzpartial"* ]] || { echo "return 1 was treated as failure: $out"; return 1; }
  [ -n "$out" ]
}

@test "state is carried by text, not only by colour (WCAG 1.4.1)" {
  # The load-bearing accessibility guarantee. In a 16-colour terminal the
  # palette belongs to the user's theme, so the warn/critical axis cannot be
  # made safe with hue; the marker is what a colourblind user, a NO_COLOR user
  # and a screen reader all actually get.
  local seen=""
  local pct out
  for pct in 50 78 93; do
    out=$(jq --argjson p "$pct" '.context_window.used_percentage=$p' \
      "${SL_REPO}/test/fixtures/full.json" |
      COLUMNS=140 SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME=instrument \
        HOME="${BATS_TEST_TMPDIR}/home" "${BASH_BIN:-bash}" "$SL" 2>/dev/null)
    case "$out" in
      *$'\033'*) echo "NO_COLOR still emitted an escape"; return 1 ;;
    esac
    seen="${seen}|${out}"
  done

  local a b c
  a=${seen#|}; a=${a%%|*}
  b=${seen#*|}; b=${b#*|}; b=${b%%|*}
  c=${seen##*|}
  [ "$a" != "$b" ] || { echo "normal and watch are identical without colour: $a"; return 1; }
  [ "$b" != "$c" ] || { echo "watch and critical are identical without colour: $b"; return 1; }
  [[ "$b" == *'!'* ]] || { echo "watch carries no marker: $b"; return 1; }
  [[ "$c" == *'!!'* ]] || { echo "critical carries no marker: $c"; return 1; }
}

@test "at most one critical token per render" {
  # Pop-out needs the alarming thing to be unique. Two reds are worth less than
  # one, so a second critical degrades to a watch.
  local out
  out=$(jq '.context_window.used_percentage=95
            | .rate_limits.five_hour.used_percentage=97
            | .rate_limits.seven_day.used_percentage=98' "${SL_REPO}/test/fixtures/full.json" |
    COLUMNS=200 SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME=instrument \
      HOME="${BATS_TEST_TMPDIR}/home" "${BASH_BIN:-bash}" "$SL" 2>/dev/null)

  local count=${out//[!!]/}
  # Three criticals would be six '!' characters; one critical plus two watches
  # is four.
  [ "${#count}" -le 4 ] || {
    echo "more than one critical token rendered: $out"
    return 1
  }
}

@test "quota stays silent while it is comfortable" {
  # Dark cockpit: the field is absent when normal, so its appearance is itself
  # the signal.
  local quiet loud
  quiet=$(jq '.rate_limits.five_hour.used_percentage=20
              | .rate_limits.seven_day.used_percentage=10' "${SL_REPO}/test/fixtures/full.json" |
    COLUMNS=160 SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME=instrument \
      HOME="${BATS_TEST_TMPDIR}/home" "${BASH_BIN:-bash}" "$SL" 2>/dev/null)
  loud=$(jq '.rate_limits.five_hour.used_percentage=94
             | .rate_limits.seven_day.used_percentage=10' "${SL_REPO}/test/fixtures/full.json" |
    COLUMNS=160 SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME=instrument \
      HOME="${BATS_TEST_TMPDIR}/home" "${BASH_BIN:-bash}" "$SL" 2>/dev/null)

  [[ "$quiet" != *"5h"* ]] || { echo "quota shown while comfortable: $quiet"; return 1; }
  [[ "$loud" == *"5h"* ]] || { echo "quota hidden while critical: $loud"; return 1; }
}

@test "max_width caps the line however wide the terminal is" {
  local w out
  for w in 400 300 210 160; do
    out=$(COLUMNS=$w SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME=instrument \
      HOME="${BATS_TEST_TMPDIR}/home" "${BASH_BIN:-bash}" "$SL" \
      <"${SL_REPO}/test/fixtures/full.json" 2>/dev/null)
    [ "${#out}" -le 120 ] || { echo "line is ${#out} wide at COLUMNS=$w, cap is 120"; return 1; }
  done
}

@test "the spacer collapses instead of overflowing on a narrow terminal" {
  local w out
  for w in 60 52 40 30 20; do
    out=$(COLUMNS=$w SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME=instrument \
      HOME="${BATS_TEST_TMPDIR}/home" "${BASH_BIN:-bash}" "$SL" \
      <"${SL_REPO}/test/fixtures/full.json" 2>/dev/null)
    [ -n "$out" ] || { echo "empty render at COLUMNS=$w"; return 1; }
    [ "${#out}" -le "$w" ] || { echo "overflow at COLUMNS=$w: ${#out} chars"; return 1; }
  done
}

@test "unknown renders as a dash, never as a credible zero" {
  # An output-token count below a thousand used to render as "0k", which reads
  # as measured-and-zero rather than as too-small-to-show.
  local out
  out=$(jq '.context_window.total_output_tokens=0
            | .context_window.total_input_tokens=562000' "${SL_REPO}/test/fixtures/full.json" |
    COLUMNS=200 SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME=dashboard \
      HOME="${BATS_TEST_TMPDIR}/home" "${BASH_BIN:-bash}" "$SL" 2>/dev/null)
  [[ "$out" != *"/0k"* ]] || { echo "unknown rendered as 0k: $out"; return 1; }
  [[ "$out" == *"562k/--"* ]] || { echo "expected a dash for the unknown side: $out"; return 1; }
}

@test "regression: a lone critical value actually renders as critical" {
  # The segment and sl_crit_owner each carry their own default threshold. When
  # they disagreed (85 in the segment, 90 in the owner) a context at 87% was
  # judged critical by the segment, found no owner, and silently degraded to
  # watch — a critical state rendered as a caution, with nothing else critical
  # on the line to justify it.
  local theme="${BATS_TEST_TMPDIR}/statuslines/themes/bare.conf"
  mkdir -p "${BATS_TEST_TMPDIR}/statuslines/themes"
  # Deliberately sets no thresholds, so both defaults are exercised.
  printf 'name = bare\nline1 = context\nseparator = " "\ncolor = off\n' >"$theme"

  local pct out
  for pct in 91 95 99; do
    out=$(jq --argjson p "$pct" '.context_window.used_percentage=$p
            | del(.rate_limits)' "${SL_REPO}/test/fixtures/full.json" |
      COLUMNS=140 SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME=bare \
        HOME="${BATS_TEST_TMPDIR}/home" XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}" \
        "${BASH_BIN:-bash}" "$SL" 2>/dev/null)
    [[ "$out" == *'!!'* ]] || {
      echo "ctx ${pct}% did not render as critical: $out"
      return 1
    }
  done

  # And the band below it must still be a watch, not a critical.
  out=$(jq '.context_window.used_percentage=80 | del(.rate_limits)' \
    "${SL_REPO}/test/fixtures/full.json" |
    COLUMNS=140 SL_NOW=1755490000 NO_COLOR=1 STATUSLINE_THEME=bare \
      HOME="${BATS_TEST_TMPDIR}/home" XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}" \
      "${BASH_BIN:-bash}" "$SL" 2>/dev/null)
  [[ "$out" != *'!!'* ]] || { echo "ctx 80% rendered as critical: $out"; return 1; }
  [[ "$out" == *'!'* ]] || { echo "ctx 80% carried no watch marker: $out"; return 1; }
}

@test "both glyphs of a bar share an East-Asian width class" {
  # A bar that pairs an Ambiguous glyph with a Neutral one changes physical
  # length as the value moves, on any terminal configured to treat ambiguous
  # characters as wide (iTerm2's "treat ambiguous-width as double-width", or a
  # CJK locale). The filled cells become two columns while the empty cells stay
  # one, so every field to the right of the bar slides as the number changes.
  #
  # The width classes are hardcoded rather than computed so this test needs no
  # tooling beyond bash: the shipped themes may only draw from these sets.
  local ambiguous='━─│┃█▒▓●○■□◆'
  local neutral='╌╍░▏▐▰▱▮▯∙'
  local ascii='#.-=*+_ |'

  local conf full empty class_full class_empty
  for conf in "${SL_REPO}"/themes/*.conf; do
    full=$(sed -n 's/^context_bar_full[[:space:]]*=[[:space:]]*"\?\(.\)"\?.*/\1/p' "$conf")
    empty=$(sed -n 's/^context_bar_empty[[:space:]]*=[[:space:]]*"\?\(.\)"\?.*/\1/p' "$conf")
    [ -n "$full" ] && [ -n "$empty" ] || continue

    class_of() {
      case "$ambiguous" in *"$1"*) printf 'ambiguous'; return ;; esac
      case "$neutral" in *"$1"*) printf 'neutral'; return ;; esac
      case "$ascii" in *"$1"*) printf 'ascii'; return ;; esac
      printf 'unknown'
    }
    class_full=$(class_of "$full")
    class_empty=$(class_of "$empty")

    [ "$class_full" != "unknown" ] || {
      echo "${conf##*/}: bar glyph '$full' is not in the approved set"
      return 1
    }
    [ "$class_empty" != "unknown" ] || {
      echo "${conf##*/}: bar glyph '$empty' is not in the approved set"
      return 1
    }
    [ "$class_full" = "$class_empty" ] || {
      echo "${conf##*/}: '$full' is $class_full but '$empty' is $class_empty — the bar will change length"
      return 1
    }
  done
}
