# ccm per VS Code

Interfaccia per ccm (Claude Code Manager) dentro VS Code. Tutta la logica resta nella CLI `ccm`:
l'estensione legge e scrive le stesse associazioni che usi da terminale.

- **Barra di stato**: profilo del workspace (per Vertex anche il progetto GCP). Diventa rossa
  se il workspace non è associato, gialla per i profili personali (disattivabile con
  `ccm.highlightPersonal`). Il tooltip mostra il profilo di ogni cartella nei workspace multi-root.
  Clic per il menu.
- **ccm: Associa profilo al workspace**: scegli il profilo e se applicarlo al solo progetto
  o alla cartella che lo contiene. Avvisa se cambi profilo a un progetto che ha già conversazioni.
- **ccm: Rimuovi associazione**, **Apri terminale Claude con profilo…**, **Mostra profili e
  progetti**, **Doctor**.
- **ccm: Configura pannello Claude Code**: imposta `claudeCode.claudeProcessWrapper` sullo shim
  di ccm, così anche il pannello ufficiale usa il profilo del workspace. All'avvio l'estensione
  controlla questa impostazione e propone di sistemarla.

Richiede ccm 0.2.0 o successivo (serve `--json`).

Installazione: `code --install-extension ccm-vscode.vsix`
