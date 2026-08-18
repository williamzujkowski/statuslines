#!/usr/bin/env bash
# Dev bootstrap: install the git hooks, report missing tooling.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ok=0
missing=()

have() { command -v "$1" >/dev/null 2>&1; }

printf 'Runtime dependencies (required to run the status line):\n'
for tool in bash jq; do
  if have "$tool"; then
    printf '  \033[32m✓\033[0m %-12s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '  \033[31m✗\033[0m %-12s missing\n' "$tool"
    missing+=("$tool")
    ok=1
  fi
done

# git is listed separately on purpose: the engine never invokes it. It reads
# .git/HEAD off the filesystem (docs/adr/0002-no-git-subprocess.md), so git is
# needed to develop here, not to run the status line.
printf '\nDevelopment dependencies:\n'
for tool in git shellcheck shfmt bats; do
  if have "$tool"; then
    printf '  \033[32m✓\033[0m %-12s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '  \033[33m!\033[0m %-12s missing - make check will fail\n' "$tool"
    missing+=("$tool")
  fi
done

if [ -d .git ]; then
  install -m 0755 scripts/commit-msg .git/hooks/commit-msg
  printf '\n\033[32m✓\033[0m installed .git/hooks/commit-msg (Conventional Commits)\n'
fi

if [ ${#missing[@]} -gt 0 ]; then
  cat <<HINT

Install the missing tools:

  macOS:   brew install ${missing[*]}
  Debian:  sudo apt-get install -y ${missing[*]}
  Arch:    sudo pacman -S ${missing[*]}

(bats may be packaged as bats-core; shfmt lives in the go-shfmt/shfmt package.)
HINT
fi

exit "$ok"
