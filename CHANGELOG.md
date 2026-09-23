# Changelog

Il formato segue [Keep a Changelog](https://keepachangelog.com/it-IT/1.1.0/) e il progetto
usa il [versionamento semantico](https://semver.org/lang/it/).

## [0.2.0] — prima versione pubblica

### Aggiunto
- CLI `ccm`: profili Team, personali e Vertex AI, ognuno con una config dir isolata.
- Associazione progetto → profilo con regola del prefisso più lungo (anche su cartelle contenitore).
- Shim `claude` fail-closed che azzera le variabili di account/provider/billing prima di ogni avvio.
- Modalità wrapper per `claudeCode.claudeProcessWrapper`: anche il pannello VS Code usa il profilo.
- `ccm which --json` e `ccm list --json`.
- Statusline di Claude Code con il profilo attivo.
- Estensione VS Code: barra di stato, associazione dalla command palette, terminale con profilo,
  doctor, configurazione del pannello.
- Installer `curl | bash` con `--with-vscode` e `--uninstall`.
