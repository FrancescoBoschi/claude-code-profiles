# shellcheck shell=bash
# ccprof — shared library. Compatible with bash 3.2 (macOS) and later.

# shellcheck disable=SC2034  # used by bin/ccprof
CCPROF_VERSION="0.5.0"
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

# Variables that select the account, provider or endpoint Claude Code uses.
# They are ALWAYS cleared before a profile is applied.
CCPROF_MANAGED_VARS="CLAUDE_CONFIG_DIR ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_USE_VERTEX
CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_FOUNDRY CLOUD_ML_REGION
ANTHROPIC_VERTEX_PROJECT_ID ANTHROPIC_VERTEX_BASE_URL ANTHROPIC_BEDROCK_BASE_URL
CCPROF_PROFILE CCPROF_KIND CCPROF_AUTH CCPROF_TAG CCM_PROFILE CCM_KIND"
# Cloud credentials: cleared only for profiles that bill through that cloud, so
# that gcloud/aws commands run by Claude in other projects keep working.
CCPROF_GCP_VARS="GOOGLE_CLOUD_PROJECT GCLOUD_PROJECT GOOGLE_APPLICATION_CREDENTIALS
CLOUDSDK_ACTIVE_CONFIG_NAME CLOUDSDK_CONFIG"
CCPROF_AWS_VARS="AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_BEARER_TOKEN_BEDROCK"

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
# CCPROF_AUTH and CCPROF_TAG are derived for profiles created before 0.5.0.
ccprof_profile_get() {
  (
    ccprof_clean_env all
    set -a; . "$(ccprof_profile_file "$1")"; set +a
    ccprof_derive_auth_tag
    eval "printf '%s' \"\${$2:-}\""
  )
}

# ccprof_clean_env [all|vertex|bedrock|<other>]
ccprof_clean_env() {
  local v list="$CCPROF_MANAGED_VARS"
  case "${1:-}" in
    all) list="$list $CCPROF_GCP_VARS $CCPROF_AWS_VARS" ;;
    vertex) list="$list $CCPROF_GCP_VARS" ;;
    bedrock) list="$list $CCPROF_AWS_VARS" ;;
  esac
  for v in $list; do unset "$v"; done
}

# Fills CCPROF_AUTH / CCPROF_TAG / CCPROF_KIND from whatever the profile file defines
# (0.5.0+: CCPROF_AUTH and CCPROF_TAG; earlier: CCPROF_KIND or CCM_KIND = team|personal|vertex).
ccprof_derive_auth_tag() {
  local legacy="${CCPROF_KIND:-${CCM_KIND:-}}"
  if [ -z "${CCPROF_AUTH:-}" ]; then
    case "$legacy" in vertex) CCPROF_AUTH=vertex ;; *) CCPROF_AUTH=subscription ;; esac
  fi
  if [ -z "${CCPROF_TAG:-}" ]; then
    case "$legacy" in personal) CCPROF_TAG=personal ;; *) CCPROF_TAG=work ;; esac
  fi
  # Legacy single "kind" (still used by JSON consumers): team | personal | vertex | bedrock | api-key
  if [ "$CCPROF_AUTH" = subscription ]; then
    if [ "$CCPROF_TAG" = personal ]; then CCPROF_KIND=personal; else CCPROF_KIND=team; fi
  else
    CCPROF_KIND="$CCPROF_AUTH"
  fi
}

ccprof_load_profile() {
  local f auth
  f="$(ccprof_profile_file "$1")"
  [ -f "$f" ] || ccprof_die "profile '$1' does not exist (profiles: $(ccprof_profile_names | tr '\n' ' '))"
  auth="$(ccprof_profile_get "$1" CCPROF_AUTH)"
  ccprof_clean_env "$auth"
  set -a; . "$f"; set +a
  ccprof_derive_auth_tag
  export CCPROF_AUTH CCPROF_TAG CCPROF_KIND
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

# API keys live in the OS keychain (macOS Keychain, or libsecret's secret-tool on Linux),
# never in profile files. Service "ccprof", account = profile name.
ccprof_secret_set() { # name key
  if command -v security >/dev/null 2>&1; then
    security add-generic-password -U -a "$1" -s ccprof -l "ccprof: $1" -w "$2" >/dev/null
  elif command -v secret-tool >/dev/null 2>&1; then
    printf '%s' "$2" | secret-tool store --label="ccprof: $1" service ccprof account "$1"
  else
    ccprof_die "no keychain found: API key profiles need the macOS Keychain or secret-tool (libsecret) on Linux"
  fi
}

ccprof_secret_get() { # name
  if command -v security >/dev/null 2>&1; then
    security find-generic-password -a "$1" -s ccprof -w 2>/dev/null
  elif command -v secret-tool >/dev/null 2>&1; then
    secret-tool lookup service ccprof account "$1" 2>/dev/null
  else
    return 1
  fi
}

ccprof_secret_delete() { # name
  if command -v security >/dev/null 2>&1; then
    security delete-generic-password -a "$1" -s ccprof >/dev/null 2>&1 || true
  elif command -v secret-tool >/dev/null 2>&1; then
    secret-tool clear service ccprof account "$1" 2>/dev/null || true
  fi
}
