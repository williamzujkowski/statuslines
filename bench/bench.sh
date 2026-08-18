#!/usr/bin/env bash
# bench.sh — enforce the latency budget in AGENTS.md §4.4.
#
# This is a gate, not a report. Claude Code debounces status line runs by
# 300 ms and ABORTS an in-flight run when a new trigger arrives, so a slow
# render is not merely sluggish — it shows the user nothing at all. That is why
# latency here is a correctness property.
#
# Two things are measured:
#   1. wall-clock render time (p50 / p95 over N runs)
#   2. the number of external processes spawned per render
#
# The spawn count matters more than it looks: each fork is roughly a
# millisecond, and it is the metric that regresses silently when someone
# reaches for sed or awk inside a segment.
set -uo pipefail

SL_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE=${FIXTURE:-${SL_REPO}/test/fixtures/full.json}
THEME=${THEME:-dashboard}
RUNS=${RUNS:-40}

# Budget (AGENTS.md §4.4). Overridable so a slow shared CI runner can be given
# headroom explicitly rather than by quietly deleting the check.
BUDGET_P95_MS=${BUDGET_P95_MS:-300}
BUDGET_SPAWNS=${BUDGET_SPAWNS:-8}

pass=0

# ── Spawn counting ────────────────────────────────────────────────────────
# A shim directory is prepended to PATH. Each shim records that it was called
# and then execs the real binary, so the render behaves normally while every
# external invocation is counted.
count_spawns() {
  local shimdir logfile real
  shimdir=$(mktemp -d) || return 1
  logfile="${shimdir}/.calls"
  : >"$logfile"

  local tool
  for tool in jq git sed awk cut date bc tr grep wc readlink basename dirname stat tput; do
    real=$(command -v "$tool" 2>/dev/null) || continue
    cat >"${shimdir}/${tool}" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "$tool" >>"$logfile"
exec "$real" "\$@"
SHIM
    chmod +x "${shimdir}/${tool}"
  done

  PATH="${shimdir}:${PATH}" COLUMNS=120 SL_NOW=1755490000 \
    STATUSLINE_THEME="$THEME" HOME=/home/user \
    bash "${SL_REPO}/statusline.sh" <"$FIXTURE" >/dev/null 2>&1

  local total
  total=$(wc -l <"$logfile" | tr -d ' ')
  printf '%s\n' "$total"

  # Report the breakdown so a regression names its own cause.
  sort "$logfile" | uniq -c | sort -rn | sed 's/^/      /' >&2

  rm -rf "$shimdir"
}

# ── Timing ────────────────────────────────────────────────────────────────
now_us() {
  if [ -n "${EPOCHREALTIME-}" ]; then
    local t=${EPOCHREALTIME/[.,]/}
    printf '%s' "$t"
  else
    # bash 3.2 has no EPOCHREALTIME. python3 is a dev-only dependency here; the
    # status line itself never needs it.
    python3 -c 'import time;print(int(time.time()*1000000))' 2>/dev/null || printf '0'
  fi
}

printf 'statuslines benchmark\n'
printf '  fixture: %s\n' "${FIXTURE##*/}"
printf '  theme:   %s\n' "$THEME"
printf '  runs:    %s\n' "$RUNS"
printf '  bash:    %s\n\n' "$BASH_VERSION"

# Warm the filesystem cache so the first run does not dominate the p50.
for _ in 1 2 3; do
  COLUMNS=120 SL_NOW=1755490000 STATUSLINE_THEME="$THEME" HOME=/home/user \
    bash "${SL_REPO}/statusline.sh" <"$FIXTURE" >/dev/null 2>&1
done

samples=""
i=0
while [ "$i" -lt "$RUNS" ]; do
  start=$(now_us)
  COLUMNS=120 SL_NOW=1755490000 STATUSLINE_THEME="$THEME" HOME=/home/user \
    bash "${SL_REPO}/statusline.sh" <"$FIXTURE" >/dev/null 2>&1
  end=$(now_us)
  samples="${samples}$(((end - start) / 1000))
"
  i=$((i + 1))
done

sorted=$(printf '%s' "$samples" | grep -v '^$' | sort -n)
count=$(printf '%s\n' "$sorted" | wc -l | tr -d ' ')
p50=$(printf '%s\n' "$sorted" | sed -n "$(((count + 1) / 2))p")
p95=$(printf '%s\n' "$sorted" | sed -n "$(((count * 95 + 99) / 100))p")
pmax=$(printf '%s\n' "$sorted" | tail -1)

printf '  p50:     %s ms\n' "$p50"
printf '  p95:     %s ms  (budget %s ms)\n' "$p95" "$BUDGET_P95_MS"
printf '  max:     %s ms\n' "$pmax"

printf '\n  external processes spawned per render:\n'
spawns=$(count_spawns)
printf '  total:   %s  (budget %s)\n' "$spawns" "$BUDGET_SPAWNS"

printf '\n'
if [ "${p95:-9999}" -gt "$BUDGET_P95_MS" ]; then
  printf '  FAIL: p95 %s ms exceeds the %s ms budget (AGENTS.md 4.4)\n' "$p95" "$BUDGET_P95_MS"
  pass=1
fi
if [ "${spawns:-99}" -gt "$BUDGET_SPAWNS" ]; then
  printf '  FAIL: %s spawns exceeds the budget of %s (AGENTS.md 4.4)\n' "$spawns" "$BUDGET_SPAWNS"
  pass=1
fi

if [ "$pass" -eq 0 ]; then
  printf '  within budget\n'
fi
exit "$pass"
