#!/usr/bin/env bash
# theme.sh — load a theme definition.
#
# Themes are parsed, never sourced. Sourcing would be shorter and faster, but a
# theme is a file users copy from the internet, and sourcing it would make
# "install this theme" mean "run this code". Parsing keeps a theme declarative,
# which is also what makes themes safe to accept as pull requests.
# See docs/adr/0001-theme-config-format.md.
#
# Format: `key = value`, one per line, `#` comments, blank lines ignored.
# Keys are validated against a strict pattern before being used to name a
# variable, so a malicious key cannot clobber shell state (CODING-STANDARDS §2).

# sl_theme_load <path>
# Populates SL_THEME_<key>. Returns non-zero if the file cannot be read.
sl_theme_load() {
  [ -r "$1" ] || return 1
  sl_theme_parse <"$1"
}

# sl_theme_parse
# Reads a theme definition from stdin. Split out from sl_theme_load so the
# single-file bundle (scripts/bundle.sh) can feed it an embedded theme without
# needing the themes directory on disk.
sl_theme_parse() {
  local line key value

  while IFS= read -r line || [ -n "$line" ]; do
    # Strip comments and surrounding whitespace.
    line=${line%%#*}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [ -n "$line" ] || continue

    case "$line" in
      *=*) ;;
      *) continue ;;
    esac

    key=${line%%=*}
    value=${line#*=}
    key=${key%"${key##*[![:space:]]}"}
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}

    # Quoted values keep their leading and trailing spaces. Separators are
    # almost always padded (" | "), and unquoted trimming would silently glue
    # every segment together — a bug that looks like a rendering fault rather
    # than a config one.
    case "$value" in
      '"'*'"')
        value=${value#\"}
        value=${value%\"}
        ;;
      "'"*"'")
        value=${value#\'}
        value=${value%\'}
        ;;
    esac

    # Allowlist the key shape. This is the check that makes `printf -v` on a
    # file-supplied name safe: without it, a key of `PATH` or `SL_FIELDS[0]`
    # would overwrite shell state.
    case "$key" in
      "" | *[!a-z0-9_]*) continue ;;
      [0-9_]*) continue ;;
    esac

    printf -v "SL_THEME_${key}" '%s' "$value"
  done

  return 0
}

# sl_theme_get <key> [fallback]
sl_theme_get() {
  local name="SL_THEME_$1"
  printf '%s' "${!name:-${2-}}"
}

# sl_theme_resolve <name>
# Maps a theme name to a path, searching the user's own theme directory first
# so a local override beats a shipped theme of the same name.
#
# The name is validated before it reaches a path, because it can come from an
# environment variable.
sl_theme_resolve() {
  local name=$1 dir

  case "$name" in
    "" | *[!a-zA-Z0-9_-]*) return 1 ;;
  esac

  for dir in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/statuslines/themes" \
    "$HOME/.claude/statuslines/themes" \
    "${SL_ROOT}/themes"; do
    if [ -r "$dir/$name.conf" ]; then
      printf '%s' "$dir/$name.conf"
      return 0
    fi
  done

  return 1
}
