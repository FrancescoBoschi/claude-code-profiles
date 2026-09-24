#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # single-quoted expressions (and the variables they use) are evaluated by check() via eval
# ccprof smoke test: isolated HOME + a fake "claude" that prints the environment it receives.
# Usage: bash tests/smoke.sh   (run it again after every change to ccprof)
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME" "$T/fakebin"
unset XDG_CONFIG_HOME CCPROF_HOME CCPROF_OVERRIDE CCPROF_BYPASS CCPROF_REAL_CLAUDE CCM_HOME CCM_OVERRIDE CCM_BYPASS CCM_REAL_CLAUDE
touch "$HOME/.bashrc"

cat > "$T/fakebin/claude" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { echo "9.9.9 (Claude Code)"; exit 0; }
echo "CFG=${CLAUDE_CONFIG_DIR:-}"
echo "VERTEX=${CLAUDE_CODE_USE_VERTEX:-}"
echo "PROJECT=${ANTHROPIC_VERTEX_PROJECT_ID:-}"
echo "GCP=${GOOGLE_CLOUD_PROJECT:-}"
echo "KEY=${ANTHROPIC_API_KEY:-}"
echo "PROFILE=${CCPROF_PROFILE:-}"
echo "ARGS=$*"
EOF
chmod +x "$T/fakebin/claude"

bash "$SRC/install.sh" >/dev/null || { echo "install failed"; exit 1; }
D="$HOME/.local/share/ccprof"
export PATH="$D/shims:$D/bin:$T/fakebin:/usr/bin:/bin"

pass=0; fail=0
line() { grep -qxF -- "$2" <<<"$1"; }   # output $1 contains exactly the line $2
check() { # description, command expected to succeed
  if eval "$2"; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi
}

mkdir -p "$T/work/app/src" "$T/work/app/special" "$T/work/core" "$T/work/with spaces" "$T/side/tool" "$T/elsewhere"

ccprof add work --type team >/dev/null
ccprof add personal --type personal >/dev/null
ccprof add side --type personal >/dev/null
ccprof add gcp --type vertex --project billing-project --region global >/dev/null
ccprof bind work "$T/work/app" >/dev/null
ccprof bind gcp "$T/work/app/special" >/dev/null
ccprof bind gcp "$T/work/core" >/dev/null
ccprof bind personal "$T/work/with spaces" >/dev/null
ccprof bind side "$T/side" >/dev/null

echo "Resolution"
out="$(cd "$T/work/app/src" && claude -c)"
check "subdirectory → work" '[[ "$out" == *"CFG=$HOME/.claude-accounts/work"* ]]'
check "arguments passed through unchanged" '[[ "$out" == *"ARGS=-c"* ]]'
out="$(cd "$T/work/app/special" && claude)"
check "longest prefix wins → gcp" '[[ "$out" == *"PROFILE=gcp"* && "$out" == *"VERTEX=1"* ]]'
out="$(cd "$T/work/with spaces" && claude)"
check "path with spaces → personal" '[[ "$out" == *"PROFILE=personal"* ]]'
out="$(cd "$T/side/tool" && claude)"
check "two personal profiles stay separate" '[[ "$out" == *"PROFILE=side"* && "$out" == *"CFG=$HOME/.claude-accounts/side"* ]]'
ln -s "$T/work/core" "$T/link-core"
out="$(cd "$T/link-core" && claude)"
check "symlink resolved → gcp" '[[ "$out" == *"PROFILE=gcp"* ]]'

echo "Variable isolation"
out="$(cd "$T/work/core" && GOOGLE_CLOUD_PROJECT=wrong ANTHROPIC_API_KEY=sk-xxx claude)"
check "GOOGLE_CLOUD_PROJECT cleared" 'line "$out" GCP='
check "ANTHROPIC_API_KEY cleared" 'line "$out" KEY='
check "correct billing project" '[[ "$out" == *"PROJECT=billing-project"* ]]'
out="$(cd "$T/work/app" && CLAUDE_CODE_USE_VERTEX=1 claude)"
check "global Vertex variable does not leak into work" 'line "$out" VERTEX='

echo "Fail-closed and exceptions"
(cd "$T/elsewhere" && claude >/dev/null 2>&1); rc=$?
check "unbound directory → refused" '[ $rc -ne 0 ]'
out="$(cd "$T/elsewhere" && claude --version)"
check "--version works everywhere" '[[ "$out" == *"9.9.9"* ]]'
out="$(cd "$T/elsewhere" && ccprof run personal -p hello)"
check "ccprof run forces the profile" '[[ "$out" == *"PROFILE=personal"* && "$out" == *"ARGS=-p hello"* ]]'
out="$(cd "$T/elsewhere" && CCPROF_BYPASS=1 claude)"
check "CCPROF_BYPASS skips ccprof" 'line "$out" PROFILE='

echo "VS Code wrapper mode"
mkdir -p "$T/ext/native-binary"; cp "$T/fakebin/claude" "$T/ext/native-binary/claude"
sed -i.bak 's/^echo "ARGS=/echo "BIN=$0"; echo "ARGS=/' "$T/ext/native-binary/claude"
out="$(cd "$T/work/core" && claude "$T/ext/native-binary/claude" auth status --json)"
check "uses the extension's binary" 'line "$out" "BIN=$T/ext/native-binary/claude"'
check "does not pass the binary as an argument" 'line "$out" "ARGS=auth status --json"'
check "applies the profile to the panel too" 'line "$out" PROFILE=gcp'
(cd "$T/elsewhere" && claude "$T/ext/native-binary/claude" --output-format stream-json >/dev/null 2>&1); rc=$?
check "panel in an unbound project → refused" '[ $rc -ne 0 ]'

echo "Management commands"
check "which succeeds in a project" '(cd "$T/work/core" && ccprof which >/dev/null)'
check "which fails outside" '! (cd "$T/elsewhere" && ccprof which >/dev/null)'
check "current prints the profile name" '[ "$(cd "$T/work/app/src" && ccprof current)" = work ]'
check "current fails outside" '! (cd "$T/elsewhere" && ccprof current >/dev/null)'
mkdir -p "$T/work/core/.claude"; echo '{"env":{"CLAUDE_CODE_USE_VERTEX":"0"}}' > "$T/work/core/.claude/settings.json"
out="$(cd "$T/work/core" && ccprof which)"
check "which flags conflicting repo settings" '[[ "$out" == *WARNING* ]]'
ccprof bind personal "$T/work/core" >/dev/null
check "rebind replaces (single line)" '[ "$(grep -c "$T/work/core" "$HOME/.config/ccprof/projects")" -eq 1 ]'
check "vertex statusline" '[[ "$(CCPROF_PROFILE=v CCPROF_KIND=vertex ANTHROPIC_VERTEX_PROJECT_ID=p ccprof statusline </dev/null)" == *"vertex p"* ]]'
check "settings.json with statusLine created" 'grep -q statusLine "$HOME/.claude-accounts/work/settings.json"'
check "profile file has mode 600" '[ "$(stat -c %a "$HOME/.config/ccprof/profiles/work.env" 2>/dev/null || stat -f %Lp "$HOME/.config/ccprof/profiles/work.env")" = 600 ]'

ccprof rename side hobby >/dev/null
out="$(cd "$T/side/tool" && claude)"
check "rename updates bindings" '[[ "$out" == *"PROFILE=hobby"* ]]'
check "rename keeps the config dir (logins kept)" '[[ "$out" == *"CFG=$HOME/.claude-accounts/side"* ]]'
check "rename removes the old profile" '[ ! -f "$HOME/.config/ccprof/profiles/side.env" ] && [[ "$(ccprof list)" == *"  hobby "* ]]'
check "rename refuses an existing name" '! ccprof rename hobby work >/dev/null 2>&1'

ccprof unbind "$T/work/with spaces" >/dev/null
check "unbind" '! (cd "$T/work/with spaces" && claude >/dev/null 2>&1)'
ccprof remove personal >/dev/null
check "remove deletes profile and bindings" '! grep -q "	personal$" "$HOME/.config/ccprof/projects"'
check "list works" 'ccprof list >/dev/null'
if command -v python3 >/dev/null; then
  J='import json,sys; d=json.load(sys.stdin)'
  mkdir -p "$T/work/app/special/.claude"; echo '{"env":{"ANTHROPIC_API_KEY":"x"}}' > "$T/work/app/special/.claude/settings.local.json"
  check "which --json valid (bound project)" '(cd "$T/work/app/special" && ccprof which --json) | python3 -c "$J; assert d[\"profile\"]==\"gcp\" and d[\"kind\"]==\"vertex\" and d[\"conflictingSettings\"]"'
  check "which --json valid (unbound)" '(cd "$T/elsewhere" && ccprof which --json) | python3 -c "$J; assert d[\"profile\"] is None"'
  mkdir -p "$T/work/a \"odd\" b"; ccprof bind work "$T/work/a \"odd\" b" >/dev/null
  check "list --json valid with quotes in paths" 'ccprof list --json | python3 -c "$J; assert any(\"odd\" in b[\"path\"] for b in d[\"bindings\"]) and d[\"shim\"].endswith(\"/shims/claude\")"'
fi
check "rc block present only once after reinstall" 'bash "$SRC/install.sh" >/dev/null && [ "$(grep -c ">>> ccprof >>>" "$HOME/.bashrc")" -eq 1 ]'

echo
echo "Migration from ccm (<= 0.3.x)"
check "ccm alias still works" '[[ "$(ccm version 2>/dev/null)" == ccprof* ]]'
check "CCM_OVERRIDE still honoured" '[[ "$(cd "$T/elsewhere" && CCM_OVERRIDE=work claude)" == *"PROFILE=work"* ]]'
H2="$T/oldhome"
mkdir -p "$H2/.config/ccm/profiles" "$H2/.local/share/ccm/bin" "$H2/.claude-accounts/old" "$T/oldproj"
printf '# ccm profile: old\nCCM_KIND=personal\nCLAUDE_CONFIG_DIR=%s\n' "$H2/.claude-accounts/old" > "$H2/.config/ccm/profiles/old.env"
printf '%s\told\n' "$T/oldproj" > "$H2/.config/ccm/projects"
printf '{\n  "statusLine": {\n    "type": "command",\n    "command": "\\"%s/.local/share/ccm/bin/ccm\\" statusline"\n  }\n}\n' "$H2" > "$H2/.claude-accounts/old/settings.json"
printf 'export FOO=1\n# >>> ccm >>>\neval "$(old ccm init)"\n# <<< ccm <<<\n' > "$H2/.bashrc"
HOME="$H2" bash "$SRC/install.sh" >/dev/null
check "config moved to ~/.config/ccprof" '[ -f "$H2/.config/ccprof/profiles/old.env" ] && [ ! -e "$H2/.config/ccm" ]'
check "old profile file migrated" 'grep -q "^CCPROF_KIND=personal" "$H2/.config/ccprof/profiles/old.env"'
check "old install path now points to the new one" '[ -L "$H2/.local/share/ccm" ] && [ -x "$H2/.local/share/ccm/shims/claude" ]'
check "old rc block replaced, rest of rc kept" '! grep -q ">>> ccm >>>" "$H2/.bashrc" && grep -q ">>> ccprof >>>" "$H2/.bashrc" && grep -q "export FOO=1" "$H2/.bashrc"'
check "statusline command updated" 'grep -q "ccprof/bin/ccprof" "$H2/.claude-accounts/old/settings.json"'
out="$(cd "$T/oldproj" && HOME="$H2" PATH="$H2/.local/share/ccprof/shims:$H2/.local/share/ccprof/bin:$T/fakebin:/usr/bin:/bin" claude)"
check "old binding still resolves" '[[ "$out" == *"PROFILE=old"* && "$out" == *"CFG=$H2/.claude-accounts/old"* ]]'
out="$(cd "$T/oldproj" && HOME="$H2" PATH="$H2/.local/share/ccm/shims:$T/fakebin:/usr/bin:/bin" claude)"
check "VS Code wrapper at the old path still works" '[[ "$out" == *"PROFILE=old"* ]]'
out="$(HOME="$H2" bash "$SRC/install.sh" --uninstall)"
check "uninstall removes the old path link" '[ ! -e "$H2/.local/share/ccm" ] && [ ! -L "$H2/.local/share/ccm" ]'

echo "Result: $pass passed, $fail failed"
[ $fail -eq 0 ]
