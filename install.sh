#!/usr/bin/env bash
# Installa ccm per l'utente corrente.
#
#   curl -fsSL https://raw.githubusercontent.com/FrancescoBoschi/claude-code-profiles/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/FrancescoBoschi/claude-code-profiles/main/install.sh | bash -s -- --with-vscode
#   ./install.sh [--with-vscode]        da un archivio o da un clone del repository
#   ./install.sh --uninstall            rimuove ccm (profili e credenziali restano)
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
    *) echo "install.sh: opzione sconosciuta: $a" >&2; exit 1 ;;
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

# ------------------------------------------------------------------ disinstallazione
if [ "$MODE" = uninstall ]; then
  while IFS= read -r f; do strip_block "$f"; done <<RC
$(rc_files)
RC
  rm -rf "${DEST:?}"
  cb="$(code_bin || true)"
  if [ -n "$cb" ] && "$cb" --uninstall-extension "$EXT_ID" >/dev/null 2>&1; then
    echo "✓ estensione VS Code rimossa"
  fi
  echo "✓ ccm disinstallato. Profili e credenziali NON sono stati toccati:"
  echo "  $CFG e ~/.claude-accounts (cancellali a mano se non servono più)"
  exit 0
fi

# ------------------------------------------------------------------ bootstrap (curl | bash)
if [ -z "$SRC" ] || [ ! -f "$SRC/bin/ccm" ]; then
  command -v curl >/dev/null || { echo "install.sh: serve curl" >&2; exit 1; }
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "Scarico l'ultima versione di ccm da $RELEASE_BASE ..."
  curl -fsSL "$RELEASE_BASE/ccm.tar.gz" | tar xz -C "$tmp"
  bash "$tmp/ccm/install.sh" ${1+"$@"}
  exit $?
fi

# ------------------------------------------------------------------ installazione
mkdir -p "$DEST"
rm -rf "${DEST:?}/bin" "${DEST:?}/lib" "${DEST:?}/shims"
cp -R "$SRC/bin" "$SRC/lib" "$SRC/shims" "$DEST/"
chmod +x "$DEST/bin/ccm" "$DEST/shims/claude"

mkdir -p "$CFG/profiles"
chmod 700 "$CFG" "$CFG/profiles"
if [ ! -f "$CFG/projects" ]; then
  printf '# ccm: <percorso assoluto><TAB><profilo> — gestito da "ccm bind"\n' > "$CFG/projects"
fi

while IFS= read -r f; do
  strip_block "$f"
  {
    echo "$BEGIN"
    echo "# Deve restare in fondo al file: lo shim di ccm deve precedere il claude reale nel PATH."
    echo "eval \"\$(\"$DEST/bin/ccm\" init)\""
    echo "$END"
  } >> "$f"
  echo "✓ configurato $f"
done <<RC
$(rc_files)
RC

echo "✓ ccm $("$DEST/bin/ccm" version | cut -d' ' -f2) installato in $DEST"

# ------------------------------------------------------------------ estensione VS Code
if [ $WITH_VSCODE = 1 ]; then
  cb="$(code_bin || true)"
  vsix=""
  for v in "$SRC"/ccm-vscode*.vsix; do [ -f "$v" ] && { vsix="$v"; break; }; done
  if [ -z "$vsix" ]; then
    vsix="$DEST/ccm-vscode.vsix"
    curl -fsSL -o "$vsix" "$RELEASE_BASE/ccm-vscode.vsix" || vsix=""
  fi
  if [ -z "$cb" ]; then
    echo "! comando 'code' non trovato: in VS Code usa Estensioni → … → Install from VSIX${vsix:+ e scegli $vsix}"
  elif [ -z "$vsix" ]; then
    echo "! impossibile scaricare l'estensione VS Code: scaricala dalla pagina Releases del repository"
  else
    "$cb" --uninstall-extension internal.ccm-vscode >/dev/null 2>&1 || true   # vecchie build locali
    "$cb" --install-extension "$vsix" --force >/dev/null
    echo "✓ estensione VS Code installata: ricarica le finestre di VS Code"
  fi
fi

echo
echo "Apri un nuovo terminale, poi:"
echo "  ccm add team --type team        # un profilo per account (vedi README)"
echo "  ccm login team"
echo "  cd ~/progetto && ccm bind team"
echo "  claude"
