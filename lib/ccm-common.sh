# shellcheck shell=bash
# ccm — shared library. Compatible with bash 3.2 (macOS) and later.

# shellcheck disable=SC2034  # used by bin/ccm
CCM_VERSION="0.3.0"
CCM_TAB="$(printf '\t')"
CCM_HOME="${CCM_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ccm}"
CCM_PROFILES_DIR="$CCM_HOME/profiles"
CCM_PROJECTS_FILE="$CCM_HOME/projects"
CCM_ACCOUNTS_DIR="${CCM_ACCOUNTS_DIR:-$HOME/.claude-accounts}"

# Variables that can change account, provider or billing project.
# They are ALWAYS cleared before a profile is applied.
CCM_MANAGED_VARS="CLAUDE_CONFIG_DIR ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_USE_VERTEX
CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_FOUNDRY CLOUD_ML_REGION
ANTHROPIC_VERTEX_PROJECT_ID ANTHROPIC_VERTEX_BASE_URL GOOGLE_CLOUD_PROJECT
GCLOUD_PROJECT GOOGLE_APPLICATION_CREDENTIALS CLOUDSDK_ACTIVE_CONFIG_NAME
CLOUDSDK_CONFIG CCM_PROFILE CCM_KIND"

ccm_die()  { printf 'ccm: %s\n' "$*" >&2; exit 1; }
ccm_warn() { printf 'ccm: %s\n' "$*" >&2; }

ccm_valid_name() {
  case "$1" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
  return 0
}

# Physical path of a directory (symlinks resolved), empty if it does not exist.
ccm_realdir() { (cd "$1" 2>/dev/null && pwd -P); }

# /Users/x/foo -> ~/foo (display only)
ccm_tilde() {
  case "$1" in
    "$HOME"|"$HOME"/*) printf '~%s\n' "${1#"$HOME"}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

ccm_profile_file() { printf '%s/%s.env\n' "$CCM_PROFILES_DIR" "$1"; }
ccm_profile_exists() { [ -f "$(ccm_profile_file "$1")" ]; }

ccm_profile_names() {
  local f
  [ -d "$CCM_PROFILES_DIR" ] || return 0
  for f in "$CCM_PROFILES_DIR"/*.env; do
    [ -f "$f" ] || continue
    f="${f##*/}"; printf '%s\n' "${f%.env}"
  done
}

# Reads one variable of a profile without touching the current environment.
ccm_profile_get() {
  (
    ccm_clean_env
    set -a; . "$(ccm_profile_file "$1")"; set +a
    eval "printf '%s' \"\${$2:-}\""
  )
}

ccm_clean_env() {
  local v
  for v in $CCM_MANAGED_VARS; do unset "$v"; done
}

ccm_load_profile() {
  local f
  f="$(ccm_profile_file "$1")"
  [ -f "$f" ] || ccm_die "profile '$1' does not exist (profiles: $(ccm_profile_names | tr '\n' ' '))"
  ccm_clean_env
  set -a; . "$f"; set +a
  export CCM_PROFILE="$1"
}

# Prints "profile<TAB>path" for the rule with the longest prefix that contains
# directory $1 (physical path). No output when nothing matches.
ccm_resolve() {
  local dir="$1" best="" bestp="" bestlen=0 p prof
  [ -f "$CCM_PROJECTS_FILE" ] || return 0
  while IFS=$'\t' read -r p prof || [ -n "$p" ]; do
    case "$p" in ''|'#'*) continue ;; esac
    case "$dir" in
      "$p"|"$p"/*)
        if [ "${#p}" -gt "$bestlen" ]; then best="$prof"; bestp="$p"; bestlen=${#p}; fi ;;
    esac
  done < "$CCM_PROJECTS_FILE"
  if [ -n "$best" ]; then printf '%s\t%s\n' "$best" "$bestp"; fi
  return 0
}

# Default target for bind/unbind: git root, otherwise the current directory.
ccm_default_target() {
  local t
  t="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$t" ] || t="$(pwd -P)"
  ccm_realdir "$t"
}

ccm_projects_remove() {
  local tmp
  [ -f "$CCM_PROJECTS_FILE" ] || return 0
  tmp="$CCM_PROJECTS_FILE.tmp.$$"
  P="$1" awk -F'\t' '$1 != ENVIRON["P"]' "$CCM_PROJECTS_FILE" > "$tmp"
  mv "$tmp" "$CCM_PROJECTS_FILE"
}

# Finds the real claude binary on PATH, skipping the ccm shim.
ccm_real_claude() {
  local d shim="$CCM_ROOT/shims/claude"
  if [ -n "${CCM_REAL_CLAUDE:-}" ]; then
    [ -x "$CCM_REAL_CLAUDE" ] && { printf '%s\n' "$CCM_REAL_CLAUDE"; return 0; }
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
