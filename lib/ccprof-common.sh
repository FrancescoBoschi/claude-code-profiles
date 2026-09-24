# shellcheck shell=bash
# ccprof — shared library. Compatible with bash 3.2 (macOS) and later.

# shellcheck disable=SC2034  # used by bin/ccprof
CCPROF_VERSION="0.4.0"
CCPROF_TAB="$(printf '\t')"
# Backward compatibility with ccm (<= 0.3.x): the old CCM_* variables still work.
for _ccprof_v in HOME OVERRIDE BYPASS REAL_CLAUDE ACCOUNTS_DIR; do
  eval "[ -n \"\${CCPROF_$_ccprof_v:-}\" ] || [ -z \"\${CCM_$_ccprof_v:-}\" ] || CCPROF_$_ccprof_v=\"\$CCM_$_ccprof_v\""
done
unset _ccprof_v
CCPROF_HOME="${CCPROF_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ccprof}"
CCPROF_PROFILES_DIR="$CCPROF_HOME/profiles"
CCPROF_PROJECTS_FILE="$CCPROF_HOME/projects"
CCPROF_ACCOUNTS_DIR="${CCPROF_ACCOUNTS_DIR:-$HOME/.claude-accounts}"

# Variables that can change account, provider or billing project.
# They are ALWAYS cleared before a profile is applied.
CCPROF_MANAGED_VARS="CLAUDE_CONFIG_DIR ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_USE_VERTEX
CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_FOUNDRY CLOUD_ML_REGION
ANTHROPIC_VERTEX_PROJECT_ID ANTHROPIC_VERTEX_BASE_URL GOOGLE_CLOUD_PROJECT
GCLOUD_PROJECT GOOGLE_APPLICATION_CREDENTIALS CLOUDSDK_ACTIVE_CONFIG_NAME
CLOUDSDK_CONFIG CCPROF_PROFILE CCPROF_KIND CCM_PROFILE CCM_KIND"

ccprof_die()  { printf 'ccprof: %s\n' "$*" >&2; exit 1; }
ccprof_warn() { printf 'ccprof: %s\n' "$*" >&2; }

ccprof_valid_name() {
  case "$1" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
  return 0
}

# Physical path of a directory (symlinks resolved), empty if it does not exist.
ccprof_realdir() { (cd "$1" 2>/dev/null && pwd -P); }

# /Users/x/foo -> ~/foo (display only)
ccprof_tilde() {
  case "$1" in
    "$HOME"|"$HOME"/*) printf '~%s\n' "${1#"$HOME"}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

ccprof_profile_file() { printf '%s/%s.env\n' "$CCPROF_PROFILES_DIR" "$1"; }
ccprof_profile_exists() { [ -f "$(ccprof_profile_file "$1")" ]; }

ccprof_profile_names() {
  local f
  [ -d "$CCPROF_PROFILES_DIR" ] || return 0
  for f in "$CCPROF_PROFILES_DIR"/*.env; do
    [ -f "$f" ] || continue
    f="${f##*/}"; printf '%s\n' "${f%.env}"
  done
}

# Reads one variable of a profile without touching the current environment.
ccprof_profile_get() {
  (
    ccprof_clean_env
    set -a; . "$(ccprof_profile_file "$1")"; set +a
    # shellcheck disable=SC2030  # runs inside the ccprof_profile_get subshell on purpose
    [ -n "${CCPROF_KIND:-}" ] || CCPROF_KIND="${CCM_KIND:-}"
    eval "printf '%s' \"\${$2:-}\""
  )
}

ccprof_clean_env() {
  local v
  for v in $CCPROF_MANAGED_VARS; do unset "$v"; done
}

ccprof_load_profile() {
  local f
  f="$(ccprof_profile_file "$1")"
  [ -f "$f" ] || ccprof_die "profile '$1' does not exist (profiles: $(ccprof_profile_names | tr '\n' ' '))"
  ccprof_clean_env
  set -a; . "$f"; set +a
  # shellcheck disable=SC2031  # unrelated to the subshell in ccprof_profile_get
  [ -n "${CCPROF_KIND:-}" ] || CCPROF_KIND="${CCM_KIND:-}"
  export CCPROF_KIND
  export CCPROF_PROFILE="$1"
}

# Prints "profile<TAB>path" for the rule with the longest prefix that contains
# directory $1 (physical path). No output when nothing matches.
ccprof_resolve() {
  local dir="$1" best="" bestp="" bestlen=0 p prof
  [ -f "$CCPROF_PROJECTS_FILE" ] || return 0
  while IFS=$'\t' read -r p prof || [ -n "$p" ]; do
    case "$p" in ''|'#'*) continue ;; esac
    case "$dir" in
      "$p"|"$p"/*)
        if [ "${#p}" -gt "$bestlen" ]; then best="$prof"; bestp="$p"; bestlen=${#p}; fi ;;
    esac
  done < "$CCPROF_PROJECTS_FILE"
  if [ -n "$best" ]; then printf '%s\t%s\n' "$best" "$bestp"; fi
  return 0
}

# Default target for bind/unbind: git root, otherwise the current directory.
ccprof_default_target() {
  local t
  t="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$t" ] || t="$(pwd -P)"
  ccprof_realdir "$t"
}

ccprof_projects_remove() {
  local tmp
  [ -f "$CCPROF_PROJECTS_FILE" ] || return 0
  tmp="$CCPROF_PROJECTS_FILE.tmp.$$"
  P="$1" awk -F'\t' '$1 != ENVIRON["P"]' "$CCPROF_PROJECTS_FILE" > "$tmp"
  mv "$tmp" "$CCPROF_PROJECTS_FILE"
}

# Finds the real claude binary on PATH, skipping the ccprof shim.
ccprof_real_claude() {
  local d shim="$CCPROF_ROOT/shims/claude"
  if [ -n "${CCPROF_REAL_CLAUDE:-}" ]; then
    [ -x "$CCPROF_REAL_CLAUDE" ] && { printf '%s\n' "$CCPROF_REAL_CLAUDE"; return 0; }
    return 1
  fi
  local IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/claude" ] && [ ! -d "$d/claude" ] && ! [ "$d/claude" -ef "$shim" ]; then
      printf '%s\n' "$d/claude"; return 0
    fi
  done
  return 1
}
