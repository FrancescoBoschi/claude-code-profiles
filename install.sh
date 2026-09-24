#!/usr/bin/env bash
# Installs ccprof for the current user.
#
#   curl -fsSL https://raw.githubusercontent.com/FrancescoBoschi/claude-code-profiles/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/FrancescoBoschi/claude-code-profiles/main/install.sh | bash -s -- --with-vscode
#   ./install.sh [--with-vscode]        from a release archive or a clone of the repository
#   ./install.sh --uninstall            removes ccprof (profiles and credentials are kept)
set -euo pipefail

CCPROF_REPO="${CCPROF_REPO:-FrancescoBoschi/claude-code-profiles}"
RELEASE_BASE="${CCPROF_RELEASE_BASE:-https://github.com/$CCPROF_REPO/releases/latest/download}"
DEST="${CCPROF_INSTALL_DIR:-$HOME/.local/share/ccprof}"
CFG="${CCPROF_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ccprof}"
EXT_ID="${CCPROF_VSCODE_ID:-francescoboschi.ccprof-vscode}"
BEGIN="# >>> ccprof >>>"
END="# <<< ccprof <<<"
OLD_DEST="$HOME/.local/share/ccm"
OLD_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/ccm"

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
  if [ -n "${CCPROF_CODE_BIN:-}" ]; then echo "$CCPROF_CODE_BIN"; return; fi
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
  if [ -f "$1" ]; then
    awk '$0=="# >>> ccm >>>"{skip=1;next} $0=="# <<< ccm <<<"{skip=0;next} !skip' "$1" > "$1.ccm.tmp" && mv "$1.ccm.tmp" "$1"
  fi
  [ -f "$1" ] || return 0
  awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$1" > "$1.ccprof.tmp"
  mv "$1.ccprof.tmp" "$1"
}

# ------------------------------------------------------------------ uninstall
if [ "$MODE" = uninstall ]; then
  while IFS= read -r f; do strip_block "$f"; done <<RC
$(rc_files)
RC
  if [ -L "$OLD_DEST" ]; then rm -f "$OLD_DEST"; fi
  rm -rf "${DEST:?}"
  cb="$(code_bin || true)"
  if [ -n "$cb" ]; then "$cb" --uninstall-extension francescoboschi.ccm-vscode >/dev/null 2>&1 || true; fi
  if [ -n "$cb" ] && "$cb" --uninstall-extension "$EXT_ID" >/dev/null 2>&1; then
    echo "✓ VS Code extension removed"
  fi
  echo "✓ ccprof uninstalled. Profiles and credentials were NOT touched:"
  echo "  $CFG and ~/.claude-accounts (delete them by hand if you no longer need them)"
  exit 0
fi

# ------------------------------------------------------------------ bootstrap (curl | bash)
if [ -z "$SRC" ] || [ ! -f "$SRC/bin/ccprof" ]; then
  command -v curl >/dev/null || { echo "install.sh: curl is required" >&2; exit 1; }
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "Downloading the latest ccprof release from $RELEASE_BASE ..."
  curl -fsSL "$RELEASE_BASE/ccprof.tar.gz" | tar xz -C "$tmp"
  bash "$tmp/ccprof/install.sh" ${1+"$@"}
  exit $?
fi

# ------------------------------------------------------------------ install
# Coming from ccm (<= 0.3.x): move profiles and bindings to the new location.
if [ -d "$OLD_CFG" ] && [ ! -L "$OLD_CFG" ] && [ ! -e "$CFG" ]; then
  mkdir -p "$(dirname "$CFG")"
  mv "$OLD_CFG" "$CFG"
  echo "✓ moved your profiles and bindings from $OLD_CFG to $CFG"
fi

mkdir -p "$DEST"
rm -rf "${DEST:?}/bin" "${DEST:?}/lib" "${DEST:?}/shims"
cp -R "$SRC/bin" "$SRC/lib" "$SRC/shims" "$DEST/"
chmod +x "$DEST/bin/ccprof" "$DEST/bin/ccm" "$DEST/shims/claude"

# Keep the old install path working: VS Code's claudeProcessWrapper and older
# statuslines may still point to ~/.local/share/ccm.
if [ "$DEST" != "$OLD_DEST" ]; then
  if [ -d "$OLD_DEST" ] && [ ! -L "$OLD_DEST" ]; then rm -rf "${OLD_DEST:?}"; fi
  if [ ! -e "$OLD_DEST" ] && [ ! -L "$OLD_DEST" ]; then ln -s "$DEST" "$OLD_DEST"; fi
fi

mkdir -p "$CFG/profiles"
chmod 700 "$CFG" "$CFG/profiles"
for f in "$CFG"/profiles/*.env; do
  [ -f "$f" ] || continue
  if grep -q '^CCM_KIND=' "$f"; then
    sed -e 's/^CCM_KIND=/CCPROF_KIND=/' -e 's/^# ccm profile:/# ccprof profile:/' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    chmod 600 "$f"
  fi
done
for s in "${CCPROF_ACCOUNTS_DIR:-${CCM_ACCOUNTS_DIR:-$HOME/.claude-accounts}}"/*/settings.json; do
  [ -f "$s" ] || continue
  if grep -q '/ccm/bin/ccm\\" statusline' "$s"; then
    sed 's#/ccm/bin/ccm\\" statusline#/ccprof/bin/ccprof\\" statusline#' "$s" > "$s.tmp" && mv "$s.tmp" "$s"
  fi
done
if [ ! -f "$CFG/projects" ]; then
  printf '# ccprof: <absolute path><TAB><profile> — managed by "ccprof bind"\n' > "$CFG/projects"
fi

while IFS= read -r f; do
  strip_block "$f"
  {
    echo "$BEGIN"
    echo "# Keep this at the end of the file: the ccprof shim must come before the real claude on PATH."
    echo "eval \"\$(\"$DEST/bin/ccprof\" init)\""
    echo "$END"
  } >> "$f"
  echo "✓ configured $f"
done <<RC
$(rc_files)
RC

echo "✓ ccprof $("$DEST/bin/ccprof" version | cut -d' ' -f2) installed in $DEST"

# ------------------------------------------------------------------ VS Code extension
if [ $WITH_VSCODE = 1 ]; then
  cb="$(code_bin || true)"
  vsix=""
  for v in "$SRC"/ccprof-vscode*.vsix; do [ -f "$v" ] && { vsix="$v"; break; }; done
  if [ -z "$vsix" ]; then
    vsix="$DEST/ccprof-vscode.vsix"
    curl -fsSL -o "$vsix" "$RELEASE_BASE/ccprof-vscode.vsix" || vsix=""
  fi
  if [ -z "$cb" ]; then
    echo "! 'code' command not found: in VS Code use Extensions → … → Install from VSIX${vsix:+ and pick $vsix}"
  elif [ -z "$vsix" ]; then
    echo "! could not download the VS Code extension: get it from the Releases page of the repository"
  else
    "$cb" --uninstall-extension internal.ccm-vscode >/dev/null 2>&1 || true   # old local builds
    "$cb" --uninstall-extension francescoboschi.ccm-vscode >/dev/null 2>&1 || true   # renamed to ccprof-vscode
    "$cb" --install-extension "$vsix" --force >/dev/null
    echo "✓ VS Code extension installed: reload your VS Code windows"
  fi
fi

echo
echo "Open a new terminal, then:"
echo "  ccprof add work --type team        # one profile per account, any name you like"
echo "  ccprof login work"
echo "  cd ~/code/project && ccprof bind work"
echo "  claude"
