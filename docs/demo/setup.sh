# shellcheck shell=bash
# Demo sandbox for the README GIF: sourced (hidden) by demo.tape.
# Creates a throw-away HOME with ccprof, three profiles, a few projects and a fake
# "claude" that only shows which profile it received. No real account is involved.
CCPROF_DEMO_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CCPROF_DEMO="${TMPDIR:-/tmp}/ccprof-demo"
rm -rf "$CCPROF_DEMO"
mkdir -p "$CCPROF_DEMO/home" "$CCPROF_DEMO/bin"
export HOME="$CCPROF_DEMO/home"
cd "$HOME" || return
touch .bashrc
unset XDG_CONFIG_HOME CCPROF_HOME CCPROF_OVERRIDE CCPROF_BYPASS CCPROF_REAL_CLAUDE
unset CLAUDE_CONFIG_DIR ANTHROPIC_API_KEY CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_BEDROCK

cat > "$CCPROF_DEMO/bin/claude" <<'FAKE'
#!/usr/bin/env bash
case "${CCPROF_AUTH:-}" in
  vertex)  provider="Google Vertex AI, billed to ${ANTHROPIC_VERTEX_PROJECT_ID:-}" ;;
  bedrock) provider="Amazon Bedrock, ${AWS_REGION:-}" ;;
  api-key) provider="Anthropic API key" ;;
  *)       provider="Claude subscription (${CCPROF_TAG:-work} account)" ;;
esac
dir="${CLAUDE_CONFIG_DIR#"$HOME"}"
printf '\n  \033[1mclaude\033[0m \033[2m(demo: no real session is started)\033[0m\n'
printf '  profile     \033[1;36m%s\033[0m\n' "${CCPROF_PROFILE:-}"
printf '  provider    %s\n' "$provider"
printf '  config dir  ~%s\n\n' "$dir"
FAKE
chmod +x "$CCPROF_DEMO/bin/claude"

bash "$CCPROF_DEMO_SRC/install.sh" >/dev/null
export PATH="$HOME/.local/share/ccprof/shims:$HOME/.local/share/ccprof/bin:$CCPROF_DEMO/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p work/client-app work/platform personal/blog Downloads/some-repo
ccprof add work     --auth subscription --tag work     >/dev/null
ccprof add personal --auth subscription --tag personal >/dev/null
ccprof add gcp-prod --auth vertex --project acme-billing --region global --gcloud-config acme >/dev/null
ccprof bind work     "$HOME/work"          >/dev/null
ccprof bind gcp-prod "$HOME/work/platform" >/dev/null
ccprof bind personal "$HOME/personal"      >/dev/null

PS1='\[\e[1;34m\]\w\[\e[0m\] \$ '
