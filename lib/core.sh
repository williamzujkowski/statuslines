#!/usr/bin/env bash
# core.sh — read and normalize the Claude Code status line payload.
#
# This is the only file that runs jq against the payload (CODING-STANDARDS §6.5).
# Segments consume the scrubbed SL_* variables it produces and never re-parse JSON.
#
# Contract (AGENTS.md §4.1):
#   * exactly ONE jq invocation for the whole payload
#   * every field optional, with an explicit default
#   * "absent" is distinguishable from "zero"
#   * nothing derived from the payload is ever interpreted as code
#
# Field reference: docs/STATUSLINE-CONTRACT.md

# Field order is shared between the jq program and the bash reader below.
# Changing one means changing the other, so they are kept adjacent and in the
# same order. Names here are the suffix: cwd -> $SL_cwd.
SL_FIELDS=(
  # identity
  session_id transcript_path prompt_id session_name remote_session
  # workspace
  cwd project_dir added_dirs git_worktree repo_host repo_owner repo_name
  # environment
  version output_style model_id model_name agent_name agent_type
  fast_mode effort thinking vim_mode
  # cost and effort
  cost_usd duration_ms api_duration_ms lines_added lines_removed
  # context window
  ctx_pct ctx_remaining_pct ctx_size ctx_in ctx_out
  usage_input usage_output cache_read cache_create exceeds_200k
  # rate limits
  rl5_pct rl5_reset rl7_pct rl7_reset
  # pull request
  pr_number pr_url pr_state pr_kind
  # dedicated worktree sessions
  wt_name wt_path wt_branch wt_original_branch
)

# Sentinel for "the payload did not carry this field". Distinguishing absent
# from zero is a correctness requirement, not a nicety: a null used_percentage
# means "no API call yet", which is not the same as 0% used, and rendering it
# as 0% is a confidently wrong number (AGENTS.md §4.1).
SL_ABSENT=$'\001'

# The jq program.
#
#   * `s` maps null to an empty string, so absent and empty collapse together
#     and the bash reader turns both into SL_ABSENT.
#   * The gsub strips control characters. That is what stops a hostile branch
#     name, directory name, or session name from smuggling an ESC into the
#     rendered line and repainting the user's terminal (CODING-STANDARDS §2).
#   * Values are terminated with RS (U+001E) rather than a newline, so a field
#     that is empty at the end of the list still round-trips. Command
#     substitution strips trailing newlines and drops NUL bytes entirely, so
#     neither of those works as a delimiter here. RS is safe precisely because
#     the gsub above has already removed every control character from the
#     values themselves, so the delimiter cannot occur inside one.
_SL_JQ_PROGRAM='
def s: if . == null then "" else (tostring | gsub("[[:cntrl:]]"; "")) end;
[
  .session_id,
  .transcript_path,
  .prompt_id,
  .session_name,
  .remote.session_id,

  (.workspace.current_dir // .cwd),
  .workspace.project_dir,
  (.workspace.added_dirs | if type == "array" then length else null end),
  .workspace.git_worktree,
  .workspace.repo.host,
  .workspace.repo.owner,
  .workspace.repo.name,

  .version,
  .output_style.name,
  .model.id,
  (.model.display_name // .model.id),
  .agent.name,
  .agent_type,
  .fast_mode,
  .effort.level,
  .thinking.enabled,
  .vim.mode,

  .cost.total_cost_usd,
  .cost.total_duration_ms,
  .cost.total_api_duration_ms,
  .cost.total_lines_added,
  .cost.total_lines_removed,

  .context_window.used_percentage,
  .context_window.remaining_percentage,
  .context_window.context_window_size,
  .context_window.total_input_tokens,
  .context_window.total_output_tokens,
  .context_window.current_usage.input_tokens,
  .context_window.current_usage.output_tokens,
  .context_window.current_usage.cache_read_input_tokens,
  .context_window.current_usage.cache_creation_input_tokens,
  .exceeds_200k_tokens,

  .rate_limits.five_hour.used_percentage,
  .rate_limits.five_hour.resets_at,
  .rate_limits.seven_day.used_percentage,
  .rate_limits.seven_day.resets_at,

  .pr.number,
  .pr.url,
  .pr.review_state,
  .pr.kind,

  .worktree.name,
  .worktree.path,
  .worktree.branch,
  .worktree.original_branch
] | .[] | s + "\u001e"
'

# sl_parse <payload>
#
# Populates SL_<name> for every entry in SL_FIELDS, each holding either a
# scrubbed string or SL_ABSENT.
#
# On failure sets SL_DEGRADED=1 with a reason and leaves every field absent.
# The renderer must surface that state rather than hide it: degrading is
# allowed, presenting degraded state as healthy is not (AGENTS.md §4.5, §7.3).
# shellcheck disable=SC2034 # SL_DEGRADED_REASON is read by sl_render in lib/render.sh
sl_parse() {
  local payload=$1
  local raw="" i value
  local -a values=()

  SL_DEGRADED=0
  SL_DEGRADED_REASON=""

  if ! command -v jq >/dev/null 2>&1; then
    SL_DEGRADED=1
    SL_DEGRADED_REASON="jq not found"
  elif [ -z "$payload" ]; then
    SL_DEGRADED=1
    SL_DEGRADED_REASON="empty payload"
  else
    raw=$(printf '%s' "$payload" | jq -j "$_SL_JQ_PROGRAM" 2>/dev/null) || raw=""
    if [ -z "$raw" ]; then
      SL_DEGRADED=1
      SL_DEGRADED_REASON="unparseable payload"
    fi
  fi

  if [ "$SL_DEGRADED" -eq 0 ]; then
    while IFS= read -r -d $'\036' value; do
      values+=("$value")
    done < <(printf '%s' "$raw")
  fi

  for i in $(sl_seq 0 $((${#SL_FIELDS[@]} - 1))); do
    if [ "$i" -lt "${#values[@]}" ] && [ -n "${values[$i]}" ]; then
      value=${values[$i]}
    else
      value=$SL_ABSENT
    fi
    printf -v "SL_${SL_FIELDS[$i]}" '%s' "$value"
  done
}

# sl_seq <from> <to> — integer sequence without spawning seq(1).
# bash 3.2 has no `${!array[@]}` ordering guarantee worth relying on here and
# every spawn costs about a millisecond of the render budget (AGENTS.md §4.4).
sl_seq() {
  local i=$1
  while [ "$i" -le "$2" ]; do
    printf '%s\n' "$i"
    i=$((i + 1))
  done
}

# sl_has <field> — true when the payload carried a usable value for this field.
sl_has() {
  local name="SL_$1"
  local value=${!name-$SL_ABSENT}
  [ "$value" != "$SL_ABSENT" ] && [ -n "$value" ]
}

# sl_get <field> [fallback] — the value, or the fallback when absent.
sl_get() {
  local name="SL_$1"
  local value=${!name-$SL_ABSENT}
  if [ "$value" = "$SL_ABSENT" ]; then
    printf '%s' "${2-}"
  else
    printf '%s' "$value"
  fi
}

# sl_int <field> [fallback] — integer value, or the fallback.
#
# Guards every arithmetic comparison in the codebase. A non-numeric value
# reaching an arithmetic test under `set -e` aborts the whole render, so
# anything that is not a clean integer becomes the fallback here instead.
sl_int() {
  local name="SL_$1"
  local value=${!name-$SL_ABSENT}
  local fallback=${2-0}
  case "$value" in
    "$SL_ABSENT" | "" | "-") printf '%s' "$fallback" ;;
    *[!0-9-]*) printf '%s' "$fallback" ;;
    *) printf '%s' "$value" ;;
  esac
}

# sl_num <field> [fallback] — float-tolerant; returns the integer part.
# Used for fields the payload documents as floats, such as the rate-limit
# percentages, which arrive as values like 23.5.
sl_num() {
  local name="SL_$1"
  local value=${!name-$SL_ABSENT}
  local fallback=${2-0}
  local whole
  case "$value" in
    "$SL_ABSENT" | "")
      printf '%s' "$fallback"
      return
      ;;
  esac
  whole=${value%%.*}
  case "$whole" in
    "" | "-") printf '%s' "$fallback" ;;
    *[!0-9-]*) printf '%s' "$fallback" ;;
    *) printf '%s' "$whole" ;;
  esac
}

# sl_bool <field> — true when the field is present and JSON-true.
sl_bool() {
  local name="SL_$1"
  local value=${!name-$SL_ABSENT}
  [ "$value" = "true" ]
}

# sl_scrub <text> [max_length]
#
# Strips control characters and bounds length. The jq program already does this
# for everything in the payload, but values read from the FILESYSTEM never pass
# through jq — the branch name in lib/segments/git.sh is read straight out of
# .git/HEAD. A repository someone else authored can name a branch anything,
# including a string of ANSI escapes, so filesystem-derived values must be
# scrubbed at their own source.
#
# Regression: test/fixtures/hostile-head/ and the git-injection test in
# test/invariants.bats.
sl_scrub() {
  local text=${1-} max=${2:-80}
  text=${text//[[:cntrl:]]/}
  if [ "${#text}" -gt "$max" ]; then
    text="${text:0:$((max - 1))}~"
  fi
  printf '%s' "$text"
}

# sl_numeric <field> — true when the field is present AND parses as a number.
#
# Needed because sl_int/sl_num fall back to 0 on garbage, which is right for
# arithmetic but wrong for display: rendering a wrong-typed used_percentage as
# "0%" is the confidently-wrong number AGENTS.md §4.1 forbids. Callers that
# display a value gate on this; callers that only compute with one do not.
sl_numeric() {
  local name="SL_$1"
  local value=${!name-$SL_ABSENT}
  case "$value" in
    "$SL_ABSENT" | "") return 1 ;;
    *[!0-9.eE+-]*) return 1 ;;
    *[0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

# sl_theme_int <key> <default> <max>
#
# A theme value used as a NUMBER, validated and bounded.
#
# Theme files are untrusted data by design (docs/adr/0001), and a value that
# reaches a printf star-width is not merely wrong when it is garbage — it is a
# denial of service. `cost_width = 40000000` makes bash build a forty-megabyte
# pad, and the render times out with no output at all. Digit-checking is not
# enough; the magnitude has to be capped too.
sl_theme_int() {
  local name="SL_THEME_$1" fallback=$2 max=${3:-200}
  local value=${!name-}
  case "$value" in
    "" | *[!0-9]*)
      printf '%s' "$fallback"
      return 0
      ;;
  esac
  if [ "$value" -gt "$max" ]; then
    printf '%s' "$max"
  else
    printf '%s' "$value"
  fi
}

# sl_now — current unix time in seconds.
#
# Injectable via SL_NOW so that anything time-dependent stays deterministic
# under test (CODING-STANDARDS §5.3). Prefers the bash builtin, which costs no
# spawn; falls back to date(1) only on bash 3.2, which has no builtin form.
sl_now() {
  if [ -n "${SL_NOW-}" ]; then
    printf '%s' "$SL_NOW"
    return 0
  fi
  if [ -n "${EPOCHSECONDS-}" ]; then
    printf '%s' "$EPOCHSECONDS"
    return 0
  fi
  # shellcheck disable=SC2059 # %()T is a printf format, not a variable format string
  if printf -v _sl_now_buf '%(%s)T' -1 2>/dev/null; then
    printf '%s' "$_sl_now_buf"
    return 0
  fi
  date +%s 2>/dev/null || printf '0'
}
