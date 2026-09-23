#!/usr/bin/env bash
# Installs ccm for the current user.
#
#   curl -fsSL https://raw.githubusercontent.com/FrancescoBoschi/claude-code-profiles/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/FrancescoBoschi/claude-code-profiles/main/install.sh | bash -s -- --with-vscode
#   ./install.sh [--with-vscode]        from a release archive or a clone of the repository
#   ./install.sh --uninstall            removes ccm (profiles and credentials are kept)
set -euo pipefail

CCM_REPO="${CCM_REPO:-FrancescoBoschi/claude-code-profiles}"
RELEASE_BASE="${CCM_RELEASE_BASE:-https://github.com/$CCM_REPO/releases/latest/download}"
DEST="${CCM_INSTALL_DIR:-$HOME/.local/share/ccm}"
CFG="${CCM_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ccm}"
EXT_ID="${CCM_VSCODE_ID:-francescoboschi.ccm-vscode}"
BEGIN="# >>> ccm >>>"
END="# <<< ccm <<<"

MODE=install
WITH_VSCODE=0
for a in ${1+"$@"}; do
  case "$a" in
    --with-vscode) WITH_VSCODE=1 ;;
    --uninstall) MODE=uninstall ;;
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option: $a" >&2; exit 1 ;;
  esac
done

SRC=""
self="${BASH_SOURCE[0]:-}"
if [ -n "$self" ] && [ -f "$self" ]; then SRC="$(cd "$(dirname "$self")" && pwd -P)"; fi

code_bin() {
  if [ -n "${CCM_CODE_BIN:-}" ]; then echo "$CCM_CODE_BIN"; return; fi
  command -v code 2>/dev/null && return
  local c="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  if [ -x "$c" ]; then echo "$c"; fi
}

rc_files() {
  local f found=0
  for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [ -f "$f" ]; then echo "$f"; found=1; fi
  done
  if [ $found = 0 ]; then
    case "${SHELL:-}" in *zsh) echo "$HOME/.zshrc" ;; *) echo "$HOME/.bashrc" ;; esac
  fi
}

strip_block() {
  [ -f "$1" ] || return 0
  awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$1" > "$1.ccm.tmp"
  mv "$1.ccm.tmp" "$1"
}

# ------------------------------------------------------------------ uninstall
if [ "$MODE" = uninstall ]; then
  while IFS= read -r f; do strip_block "$f"; done <<RC
$(rc_files)
RC
  rm -rf "${DEST:?}"
  cb="$(code_bin || true)"
  if [ -n "$cb" ] && "$cb" --uninstall-extension "$EXT_ID" >/dev/null 2>&1; then
    echo "✓ VS Code extension removed"
  fi
  echo "✓ ccm uninstalled. Profiles and credentials were NOT touched:"
  echo "  $CFG and ~/.claude-accounts (delete them by hand if you no longer need them)"
  exit 0
fi

# ------------------------------------------------------------------ bootstrap (curl | bash)
if [ -z "$SRC" ] || [ ! -f "$SRC/bin/ccm" ]; then
  command -v curl >/dev/null || { echo "install.sh: curl is required" >&2; exit 1; }
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "Downloading the latest ccm release from $RELEASE_BASE ..."
  curl -fsSL "$RELEASE_BASE/ccm.tar.gz" | tar xz -C "$tmp"
  bash "$tmp/ccm/install.sh" ${1+"$@"}
  exit $?
fi

# ------------------------------------------------------------------ install
mkdir -p "$DEST"
rm -rf "${DEST:?}/bin" "${DEST:?}/lib" "${DEST:?}/shims"
cp -R "$SRC/bin" "$SRC/lib" "$SRC/shims" "$DEST/"
chmod +x "$DEST/bin/ccm" "$DEST/shims/claude"

mkdir -p "$CFG/profiles"
chmod 700 "$CFG" "$CFG/profiles"
if [ ! -f "$CFG/projects" ]; then
  printf '# ccm: <absolute path><TAB><profile> — managed by "ccm bind"\n' > "$CFG/projects"
fi

while IFS= read -r f; do
  strip_block "$f"
  {
    echo "$BEGIN"
    echo "# Keep this at the end of the file: the ccm shim must come before the real claude on PATH."
    echo "eval \"\$(\"$DEST/bin/ccm\" init)\""
    echo "$END"
  } >> "$f"
  echo "✓ configured $f"
done <<RC
$(rc_files)
RC

echo "✓ ccm $("$DEST/bin/ccm" version | cut -d' ' -f2) installed in $DEST"

# ------------------------------------------------------------------ VS Code extension
if [ $WITH_VSCODE = 1 ]; then
  cb="$(code_bin || true)"
  vsix=""
  for v in "$SRC"/ccm-vscode*.vsix; do [ -f "$v" ] && { vsix="$v"; break; }; done
  if [ -z "$vsix" ]; then
    vsix="$DEST/ccm-vscode.vsix"
    curl -fsSL -o "$vsix" "$RELEASE_BASE/ccm-vscode.vsix" || vsix=""
  fi
  if [ -z "$cb" ]; then
    echo "! 'code' command not found: in VS Code use Extensions → … → Install from VSIX${vsix:+ and pick $vsix}"
  elif [ -z "$vsix" ]; then
    echo "! could not download the VS Code extension: get it from the Releases page of the repository"
  else
    "$cb" --uninstall-extension internal.ccm-vscode >/dev/null 2>&1 || true   # old local builds
    "$cb" --install-extension "$vsix" --force >/dev/null
    echo "✓ VS Code extension installed: reload your VS Code windows"
  fi
fi

echo
echo "Open a new terminal, then:"
echo "  ccm add work --type team        # one profile per account, any name you like"
echo "  ccm login work"
echo "  cd ~/code/project && ccm bind work"
echo "  claude"
