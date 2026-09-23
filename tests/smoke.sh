#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # le espressioni tra apici singoli (e le variabili che usano) sono valutate da check() con eval
# Smoke test di ccm: HOME isolato + finto "claude" che stampa l'ambiente ricevuto.
# Uso: bash tests/smoke.sh   (da rilanciare dopo ogni aggiornamento di ccm)
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME" "$T/fakebin"
unset XDG_CONFIG_HOME CCM_HOME CCM_OVERRIDE CCM_BYPASS CCM_REAL_CLAUDE
touch "$HOME/.bashrc"

cat > "$T/fakebin/claude" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { echo "9.9.9 (Claude Code)"; exit 0; }
echo "CFG=${CLAUDE_CONFIG_DIR:-}"
echo "VERTEX=${CLAUDE_CODE_USE_VERTEX:-}"
echo "PROJECT=${ANTHROPIC_VERTEX_PROJECT_ID:-}"
echo "GCP=${GOOGLE_CLOUD_PROJECT:-}"
echo "KEY=${ANTHROPIC_API_KEY:-}"
echo "PROFILE=${CCM_PROFILE:-}"
echo "ARGS=$*"
EOF
chmod +x "$T/fakebin/claude"

bash "$SRC/install.sh" >/dev/null || { echo "install fallito"; exit 1; }
D="$HOME/.local/share/ccm"
export PATH="$D/shims:$D/bin:$T/fakebin:/usr/bin:/bin"

pass=0; fail=0
line() { grep -qxF -- "$2" <<<"$1"; }   # $1 contiene esattamente la riga $2
check() { # descrizione, comando atteso vero
  if eval "$2"; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi
}

mkdir -p "$T/work/team-app/src" "$T/work/team-app/special" "$T/work/core" "$T/work/con spazi" "$T/altro"

ccm add team --type team >/dev/null
ccm add mio --type personal >/dev/null
ccm add vertex --type vertex --project progetto-billing --region global >/dev/null
ccm bind team "$T/work/team-app" >/dev/null
ccm bind vertex "$T/work/team-app/special" >/dev/null
ccm bind vertex "$T/work/core" >/dev/null
ccm bind mio "$T/work/con spazi" >/dev/null

echo "Risoluzione"
out="$(cd "$T/work/team-app/src" && claude -c)"
check "sottocartella → team" '[[ "$out" == *"CFG=$HOME/.claude-accounts/team"* ]]'
check "argomenti passati invariati" '[[ "$out" == *"ARGS=-c"* ]]'
out="$(cd "$T/work/team-app/special" && claude)"
check "prefisso più lungo vince → vertex" '[[ "$out" == *"PROFILE=vertex"* && "$out" == *"VERTEX=1"* ]]'
out="$(cd "$T/work/con spazi" && claude)"
check "percorso con spazi → mio" '[[ "$out" == *"PROFILE=mio"* ]]'
ln -s "$T/work/core" "$T/link-core"
out="$(cd "$T/link-core" && claude)"
check "symlink risolto → vertex" '[[ "$out" == *"PROFILE=vertex"* ]]'

echo "Isolamento variabili"
out="$(cd "$T/work/core" && GOOGLE_CLOUD_PROJECT=sbagliato ANTHROPIC_API_KEY=sk-xxx claude)"
check "GOOGLE_CLOUD_PROJECT azzerata" 'line "$out" GCP='
check "ANTHROPIC_API_KEY azzerata" 'line "$out" KEY='
check "progetto di billing corretto" '[[ "$out" == *"PROJECT=progetto-billing"* ]]'
out="$(cd "$T/work/team-app" && CLAUDE_CODE_USE_VERTEX=1 claude)"
check "Vertex globale non contamina team" 'line "$out" VERTEX='

echo "Fail-closed ed eccezioni"
(cd "$T/altro" && claude >/dev/null 2>&1); rc=$?
check "directory non associata → bloccato" '[ $rc -ne 0 ]'
out="$(cd "$T/altro" && claude --version)"
check "--version funziona ovunque" '[[ "$out" == *"9.9.9"* ]]'
out="$(cd "$T/altro" && ccm run mio -p ciao)"
check "ccm run forza il profilo" '[[ "$out" == *"PROFILE=mio"* && "$out" == *"ARGS=-p ciao"* ]]'
out="$(cd "$T/altro" && CCM_BYPASS=1 claude)"
check "CCM_BYPASS salta ccm" 'line "$out" PROFILE='

echo "Modalità wrapper VS Code"
mkdir -p "$T/ext/native-binary"; cp "$T/fakebin/claude" "$T/ext/native-binary/claude"
sed -i.bak 's/^echo "ARGS=/echo "BIN=$0"; echo "ARGS=/' "$T/ext/native-binary/claude"
out="$(cd "$T/work/core" && claude "$T/ext/native-binary/claude" auth status --json)"
check "usa il binario dell'estensione" 'line "$out" "BIN=$T/ext/native-binary/claude"'
check "non passa il binario come argomento" 'line "$out" "ARGS=auth status --json"'
check "applica il profilo anche al pannello" 'line "$out" PROFILE=vertex'
(cd "$T/altro" && claude "$T/ext/native-binary/claude" --output-format stream-json >/dev/null 2>&1); rc=$?
check "pannello in progetto non associato → bloccato" '[ $rc -ne 0 ]'

echo "Comandi di gestione"
check "which ok in progetto" '(cd "$T/work/core" && ccm which >/dev/null)'
check "which fallisce fuori" '! (cd "$T/altro" && ccm which >/dev/null)'
mkdir -p "$T/work/core/.claude"; echo '{"env":{"CLAUDE_CODE_USE_VERTEX":"0"}}' > "$T/work/core/.claude/settings.json"
out="$(cd "$T/work/core" && ccm which)"
check "which segnala settings in conflitto" '[[ "$out" == *ATTENZIONE* ]]'
ccm bind mio "$T/work/core" >/dev/null
check "rebind sostituisce (una sola riga)" '[ "$(grep -c "$T/work/core" "$HOME/.config/ccm/projects")" -eq 1 ]'
check "statusline vertex" '[[ "$(CCM_PROFILE=v CCM_KIND=vertex ANTHROPIC_VERTEX_PROJECT_ID=p ccm statusline </dev/null)" == *"vertex p"* ]]'
check "settings.json con statusLine creato" 'grep -q statusLine "$HOME/.claude-accounts/team/settings.json"'
check "permessi 600 sul profilo" '[ "$(stat -c %a "$HOME/.config/ccm/profiles/team.env" 2>/dev/null || stat -f %Lp "$HOME/.config/ccm/profiles/team.env")" = 600 ]'
ccm unbind "$T/work/con spazi" >/dev/null
check "unbind" '! (cd "$T/work/con spazi" && claude >/dev/null 2>&1)'
ccm remove mio >/dev/null
check "remove elimina profilo e binding" '! grep -q "	mio$" "$HOME/.config/ccm/projects"'
check "list funziona" 'ccm list >/dev/null'
if command -v python3 >/dev/null; then
  J='import json,sys; d=json.load(sys.stdin)'
  mkdir -p "$T/work/team-app/special/.claude"; echo '{"env":{"ANTHROPIC_API_KEY":"x"}}' > "$T/work/team-app/special/.claude/settings.local.json"
  check "which --json valido (progetto)" '(cd "$T/work/team-app/special" && ccm which --json) | python3 -c "$J; assert d[\"profile\"]==\"vertex\" and d[\"kind\"]==\"vertex\" and d[\"conflictingSettings\"]"'
  check "which --json valido (non associato)" '(cd "$T/altro" && ccm which --json) | python3 -c "$J; assert d[\"profile\"] is None"'
  mkdir -p "$T/work/a \"strano\" b"; ccm bind team "$T/work/a \"strano\" b" >/dev/null
  check "list --json valido con virgolette nei path" 'ccm list --json | python3 -c "$J; assert any(\"strano\" in b[\"path\"] for b in d[\"bindings\"]) and d[\"shim\"].endswith(\"/shims/claude\")"'
fi
check "blocco rc presente una sola volta dopo reinstall" 'bash "$SRC/install.sh" >/dev/null && [ "$(grep -c ">>> ccm >>>" "$HOME/.bashrc")" -eq 1 ]'

echo
echo "Risultato: $pass ok, $fail falliti"
[ $fail -eq 0 ]
