#!/usr/bin/env bats
# Unit tests for the parsing and formatting primitives in lib/.

setup() {
  SL_REPO=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
  SL_ROOT=$SL_REPO
  export SL_ROOT
  . "${SL_REPO}/lib/core.sh"
  . "${SL_REPO}/lib/colors.sh"
  . "${SL_REPO}/lib/theme.sh"
  sl_colors_init
}

@test "sl_parse distinguishes absent from zero" {
  sl_parse '{"context_window":{"used_percentage":null,"context_window_size":200000}}'
  run sl_has ctx_pct
  [ "$status" -ne 0 ]

  sl_parse '{"context_window":{"used_percentage":0,"context_window_size":200000}}'
  run sl_has ctx_pct
  [ "$status" -eq 0 ]
  [ "$(sl_get ctx_pct)" = "0" ]
}

@test "sl_parse strips control characters from values" {
  sl_parse "$(printf '{"model":{"display_name":"O\\u001b[31mpus"}}')"
  case "$(sl_get model_name)" in
    *$'\033'*) return 1 ;;
  esac
  [ "$(sl_get model_name)" = "O[31mpus" ]
}

@test "sl_int falls back rather than aborting on a non-numeric value" {
  sl_parse '{"cost":{"total_duration_ms":"ages"}}'
  [ "$(sl_int duration_ms 0)" = "0" ]
  [ "$(sl_int duration_ms 42)" = "42" ]
}

@test "sl_num handles the float rate-limit percentages" {
  sl_parse '{"rate_limits":{"five_hour":{"used_percentage":23.7,"resets_at":1700000000}}}'
  [ "$(sl_num rl5_pct)" = "23" ]
  # sl_int must REJECT it: the value is a float, and treating it as an integer
  # is the bug this pair of helpers exists to prevent.
  [ "$(sl_int rl5_pct 999)" = "999" ]
}

@test "sl_numeric rejects a wrong-typed value that sl_int would zero" {
  sl_parse '{"context_window":{"used_percentage":"most"}}'
  run sl_numeric ctx_pct
  [ "$status" -ne 0 ]
  # sl_int is still safe to call, it just yields the fallback.
  [ "$(sl_int ctx_pct 0)" = "0" ]
}

@test "sl_bool is true only for JSON true" {
  sl_parse '{"fast_mode":true,"thinking":{"enabled":false}}'
  run sl_bool fast_mode
  [ "$status" -eq 0 ]
  run sl_bool thinking
  [ "$status" -ne 0 ]
}

@test "a trailing absent field still lands in the right slot" {
  # The last field in SL_FIELDS is wt_original_branch. If the delimiter handling
  # were wrong, a payload with an early field set and everything after it absent
  # would shift values into neighbouring slots.
  sl_parse '{"session_id":"abc"}'
  [ "$(sl_get session_id)" = "abc" ]
  run sl_has wt_original_branch
  [ "$status" -ne 0 ]
  run sl_has model_name
  [ "$status" -ne 0 ]
}

@test "sl_theme_load keeps quoted whitespace and trims unquoted values" {
  local tmp="${BATS_TEST_TMPDIR}/t.conf"
  printf 'separator = " | "\nname =   spaced   \n' >"$tmp"
  sl_theme_load "$tmp"
  [ "$(sl_theme_get separator)" = " | " ]
  [ "$(sl_theme_get name)" = "spaced" ]
}

@test "sl_theme_load ignores keys that could clobber shell state" {
  local tmp="${BATS_TEST_TMPDIR}/evil.conf"
  local before=$PATH
  printf 'PATH = /evil\nSL_FIELDS = boom\nok_key = fine\n' >"$tmp"
  sl_theme_load "$tmp"
  [ "$PATH" = "$before" ]
  [ "$(sl_theme_get ok_key)" = "fine" ]
}

@test "sl_theme_resolve rejects a traversing name" {
  run sl_theme_resolve '../../etc/passwd'
  [ "$status" -ne 0 ]
  run sl_theme_resolve 'default'
  [ "$status" -eq 0 ]
}

@test "sl_strip_ansi removes SGR and leaves the text" {
  local painted
  painted=$(sl_paint red "hello")
  [ "$(sl_strip_ansi "$painted")" = "hello" ]
  [ "$(sl_width "$painted")" = "5" ]
}

@test "sl_paint emits no escapes when color is disabled" {
  SL_COLOR_ENABLED=0
  local out
  out=$(sl_paint red "hello")
  [ "$out" = "hello" ]
}

@test "sl_threshold_color ramps in the right direction" {
  [ "$(sl_threshold_color 10 60 85)" = "green" ]
  [ "$(sl_threshold_color 70 60 85)" = "yellow" ]
  [ "$(sl_threshold_color 90 60 85)" = "red" ]
}

@test "critical thresholds use one shared resolver" {
  unset SL_THEME_context_crit SL_THEME_ratelimit_crit
  sl_threshold_default context_crit
  [ "$_SL_THRESHOLD_VALUE" = "90" ]
  sl_threshold_default ratelimit_crit
  [ "$_SL_THRESHOLD_VALUE" = "90" ]

  SL_THEME_context_crit=85
  SL_THEME_ratelimit_crit=95
  sl_threshold_default context_crit
  [ "$_SL_THRESHOLD_VALUE" = "85" ]
  sl_threshold_default ratelimit_crit
  [ "$_SL_THRESHOLD_VALUE" = "95" ]

  run sl_threshold_default unknown
  [ "$status" -ne 0 ]
}

@test "sl_now is injectable for determinism" {
  SL_NOW=1700000000
  [ "$(sl_now)" = "1700000000" ]
}

@test "sl_theme_parse strips control characters from values" {
  # ADR-0001 promises that installing a theme cannot harm you. That promise was
  # unenforced: theme values are rendered straight to the terminal, so a
  # separator containing ESC [ 2 J cleared the screen on every render. No theme
  # value legitimately contains a control character.
  local tmp="${BATS_TEST_TMPDIR}/evil.conf"
  printf 'separator = "\033[2J\033[H"\ncontext_label = \033[5mBLINK\nline1 = dir \033[31mevil\n' >"$tmp"
  sl_theme_load "$tmp"

  local v
  for key in separator context_label line1; do
    v=$(sl_theme_get "$key")
    case "$v" in
      *$'\033'*) echo "escape survived in theme key $key: $(printf '%q' "$v")"; return 1 ;;
    esac
  done
  # The printable remainder is kept, so the theme still does something sane.
  [ "$(sl_theme_get context_label)" = "[5mBLINK" ]
}

@test "sl_scrub removes control characters and bounds length" {
  local out
  out=$(sl_scrub "$(printf 'a\033[31mb\007c')" 80)
  case "$out" in *$'\033'* | *$'\007'*) return 1 ;; esac
  [ "$out" = "a[31mbc" ]

  out=$(sl_scrub "$(printf 'x%.0s' $(seq 1 100))" 10)
  [ "${#out}" -eq 10 ]
}

@test "sl_theme_int validates and caps a theme-supplied number" {
  # Theme files are untrusted data by design (ADR-0001). A value that reaches a
  # printf star-width is not merely wrong when it is garbage — it is a denial of
  # service: cost_width = 40000000 makes bash build a forty-megabyte pad and the
  # render times out with no output at all. Digit-checking alone would not have
  # helped, because 40000000 is all digits; the magnitude has to be capped.
  SL_THEME_probe=40000000
  [ "$(sl_theme_int probe 0 40)" = "40" ]

  SL_THEME_probe=7
  [ "$(sl_theme_int probe 0 40)" = "7" ]

  SL_THEME_probe="40; rm -rf /"
  [ "$(sl_theme_int probe 3 40)" = "3" ]

  SL_THEME_probe=""
  [ "$(sl_theme_int probe 5 40)" = "5" ]

  unset SL_THEME_probe
  [ "$(sl_theme_int probe 9 40)" = "9" ]
}

@test "every printf field width in a segment is bounded" {
  # The guard above only helps where it is actually used. This asserts that no
  # segment passes a raw theme value into a star-width, which is the shape the
  # bug took.
  local hits
  hits=$(grep -n "printf '%\*" "${SL_REPO}"/lib/segments/*.sh || true)
  [ -n "$hits" ] || skip "no star-width printf in any segment"

  local line
  while IFS= read -r line; do
    case "$line" in
      *sl_theme_int*) ;;
      *) echo "unbounded field width: $line"; return 1 ;;
    esac
  done <<<"$hits"
}
