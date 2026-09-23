# shellcheck shell=bash
# ccm — libreria condivisa. Compatibile con bash 3.2 (macOS) e successivi.

# shellcheck disable=SC2034  # usata da bin/ccm
CCM_VERSION="0.2.0"
CCM_TAB="$(printf '\t')"
CCM_HOME="${CCM_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ccm}"
CCM_PROFILES_DIR="$CCM_HOME/profiles"
CCM_PROJECTS_FILE="$CCM_HOME/projects"
CCM_ACCOUNTS_DIR="${CCM_ACCOUNTS_DIR:-$HOME/.claude-accounts}"

# Variabili che possono cambiare account, provider o progetto di billing.
# Vengono SEMPRE azzerate prima di applicare un profilo.
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

# Percorso fisico di una directory (symlink risolti), vuoto se non esiste.
ccm_realdir() { (cd "$1" 2>/dev/null && pwd -P); }

# /Users/x/foo -> ~/foo (solo per la visualizzazione)
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

# Legge una variabile di un profilo senza toccare l'ambiente corrente.
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
  [ -f "$f" ] || ccm_die "profilo '$1' inesistente (profili: $(ccm_profile_names | tr '\n' ' '))"
  ccm_clean_env
  set -a; . "$f"; set +a
  export CCM_PROFILE="$1"
}

# Stampa "profilo<TAB>percorso" della regola con il prefisso più lungo che
# contiene la directory $1 (percorso fisico). Nessun output se non c'è match.
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

# Directory "radice" di default per bind/unbind: root git, altrimenti cwd.
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

# Trova il binario claude reale nel PATH, saltando lo shim di ccm.
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
