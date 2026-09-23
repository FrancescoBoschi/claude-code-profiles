# Contribuire

Grazie! Qualche regola per mantenere ccm semplice e affidabile.

## Principi
- **La CLI è l'unica fonte di verità.** L'estensione VS Code non contiene logica sui profili:
  chiama `ccm ... --json`. Una nuova funzionalità nasce nella CLI.
- **Fail-closed.** Nel dubbio `claude` non parte: meglio un errore chiaro che l'account sbagliato.
- **Nessuna dipendenza** oltre a bash, awk, sed e (per Vertex) gcloud.

## Compatibilità shell
Gli script devono girare con la **bash 3.2 di macOS**. Quindi niente array associativi,
`mapfile`, `${var,,}`, `readarray`. Con `set -u` usa `${1+"$@"}` al posto di `"$@"`.

## Test
```bash
bash tests/smoke.sh          # CLI e shim (HOME temporaneo, finto claude)
node vscode/test/run.js      # estensione, con API vscode simulata e ccm reale
shellcheck -s bash bin/ccm shims/claude lib/ccm-common.sh install.sh tests/smoke.sh
```
La CI li esegue su Linux e macOS a ogni push e pull request.

## Rilasciare una versione
1. Aggiorna `CCM_VERSION` in `lib/ccm-common.sh`, `version` in `vscode/package.json` e `CHANGELOG.md`.
2. `git tag vX.Y.Z && git push --tags`: la GitHub Action crea la release con
   `ccm.tar.gz` e `ccm-vscode.vsix`.
