# ccm — Claude Code Manager

[![CI](https://github.com/FrancescoBoschi/claude-code-profiles/actions/workflows/ci.yml/badge.svg)](https://github.com/FrancescoBoschi/claude-code-profiles/actions/workflows/ci.yml)
[![Licenza: MIT](https://img.shields.io/badge/licenza-MIT-blue.svg)](LICENSE)

**Un account Claude Code per ogni progetto, applicato in automatico.**

Se usi Claude Code con più account (un piano Team aziendale, un account personale, la
fatturazione su Google Vertex AI) ccm ti permette di associare ogni progetto al suo account
una volta sola. Da lì lanci `claude` come sempre, da terminale o dal pannello di VS Code, e
parte con l'account giusto: niente logout, niente variabili da ricordare, nessun rischio di
fatturare sul progetto sbagliato.

```text
~/work/cliente-a   →  team      (piano Team aziendale)
~/work/piattaforma →  vertex    (billing sul progetto GCP)
~/personal         →  mio       (account personale)
```

> **Progetto non ufficiale**, non affiliato ad Anthropic. Claude e Claude Code sono marchi
> di Anthropic. ccm si appoggia a meccanismi di Claude Code che funzionano ma non sono tutti
> documentati ufficialmente (vedi [Limiti noti](#limiti-noti)).

## Indice

- [Requisiti](#requisiti)
- [Installazione](#installazione)
- [Configurazione in 5 minuti](#configurazione-in-5-minuti)
- [VS Code](#vs-code)
- [Uso quotidiano](#uso-quotidiano)
- [Comandi](#comandi)
- [Come funziona](#come-funziona)
- [Conversazioni esistenti](#conversazioni-esistenti)
- [Risoluzione dei problemi](#risoluzione-dei-problemi)
- [Limiti noti](#limiti-noti)
- [Aggiornare e disinstallare](#aggiornare-e-disinstallare)
- [Sviluppo](#sviluppo)

## Requisiti

- **macOS o Linux** (su Windows: dentro WSL). Funziona con zsh e bash, compresa la bash 3.2 di macOS.
- **Claude Code** già installato (`claude --version`).
- Per i profili Vertex AI: **Google Cloud SDK** (`gcloud`) e un progetto GCP con i modelli
  Claude abilitati in Vertex AI.
- Per l'estensione: **VS Code** con l'estensione ufficiale Claude Code.

## Installazione

### Opzione A — un comando

```bash
curl -fsSL https://raw.githubusercontent.com/FrancescoBoschi/claude-code-profiles/main/install.sh | bash -s -- --with-vscode
```

Installa la CLI e, se trova il comando `code`, anche l'estensione VS Code.
Senza `--with-vscode` installa solo la CLI.

### Opzione B — dalla pagina Releases

1. Scarica `ccm.tar.gz` dall'[ultima release](https://github.com/FrancescoBoschi/claude-code-profiles/releases/latest).
2. Nel terminale:
   ```bash
   tar xzf ccm.tar.gz && cd ccm
   ./install.sh --with-vscode
   ```

### Opzione C — dal sorgente

```bash
git clone https://github.com/FrancescoBoschi/claude-code-profiles.git && cd ccm
./install.sh
```

### Cosa fa l'installer

- copia i file in `~/.local/share/ccm`;
- crea `~/.config/ccm/` (profili e associazioni);
- aggiunge in fondo a `~/.zshrc` / `~/.bashrc` un blocco delimitato da `# >>> ccm >>>`
  che mette lo shim di ccm in testa al PATH.

Poi **apri un nuovo terminale** e controlla:

```bash
ccm doctor
```

La prima riga deve dire `✓ lo shim ccm è il primo 'claude' nel PATH`.

## Configurazione in 5 minuti

### 1. Crea un profilo per ogni account

Lo fai **una volta sola**, da qualunque cartella.

```bash
ccm add team --type team            # account aziendale con piano Team
ccm add mio  --type personal        # account personale
ccm add vertex --type vertex --project ID-PROGETTO-GCP --region global
```

Il nome del profilo lo scegli tu. Senza opzioni, `ccm add <nome>` chiede i dati in modo interattivo.
Per Vertex puoi aggiungere `--gcloud-config NOME` per usare una configurazione gcloud specifica.

### 2. Fai il primo login di ogni profilo

```bash
ccm login team      # si apre Claude Code: completa il login (se non compare, digita /login), poi /exit
ccm login mio
ccm login vertex    # per Vertex esegue: gcloud auth application-default login
```

Ogni profilo tiene le sue credenziali: dopo il primo login non dovrai più rifarlo.

### 3. Associa i progetti

Lo fai **una volta per progetto**, dalla cartella del progetto:

```bash
cd ~/work/cliente-a && ccm bind team
cd ~/work/piattaforma && ccm bind vertex
```

`bind` associa la root del repository git, quindi va bene lanciarlo anche da una sottocartella.

**Scorciatoia:** associa le cartelle che raccolgono più progetti. Vince sempre l'associazione
più specifica, quindi puoi fare eccezioni sui singoli progetti:

```bash
ccm bind team ~/work          # tutti i progetti in ~/work, anche quelli futuri
ccm bind mio  ~/personal
ccm bind vertex ~/work/piattaforma   # eccezione: questo va su Vertex
```

### 4. Verifica

```bash
cd ~/work/cliente-a
ccm which         # mostra il profilo che verrà usato qui
claude            # la statusline in basso mostra "ccm: team"; /status mostra l'account
```

## VS Code

L'estensione ufficiale di Claude Code avvia il **proprio** binario `claude`, senza passare dal
PATH: senza configurazione il pannello userebbe l'account di default e ignorerebbe ccm.
La soluzione è l'impostazione `claudeCode.claudeProcessWrapper`, che ccm sa gestire.

### Con l'estensione ccm (consigliato)

1. Installala con `./install.sh --with-vscode`, oppure scarica `ccm-vscode.vsix` dalla
   [pagina Releases](https://github.com/FrancescoBoschi/claude-code-profiles/releases/latest) e in VS Code vai su
   **Estensioni → `…` → Install from VSIX…**.
2. Ricarica VS Code. Al primo avvio ti propone di configurare il pannello di Claude Code:
   scegli **Configura**, poi **Ricarica finestra**.

Cosa ottieni:

- **Barra di stato** (in basso a sinistra): il profilo del workspace, per esempio
  `ccm: team` o `ccm: vertex · progetto`. È **rossa** se il workspace non è associato,
  **gialla** per i profili personali. Il tooltip mostra il dettaglio di ogni cartella. Clic per il menu.
- **Command palette** (`Cmd/Ctrl+Shift+P` → "ccm"):
  - *Associa profilo al workspace* — anche all'intera cartella contenitore;
  - *Rimuovi associazione*;
  - *Apri terminale Claude con profilo…* — un profilo diverso, una tantum;
  - *Mostra profili e progetti*, *Doctor*;
  - *Configura pannello Claude Code*.

Impostazioni: `ccm.path` (percorso di ccm, se non è quello standard), `ccm.highlightPersonal`,
`ccm.checkClaudeWrapper`.

### Senza l'estensione ccm

Nei settings **utente** di VS Code (`Preferences: Open User Settings (JSON)`) aggiungi,
sostituendo il tuo nome utente:

```json
"claudeCode.claudeProcessWrapper": "/Users/TUO-NOME-UTENTE/.local/share/ccm/shims/claude"
```

poi `Developer: Reload Window`.

## Uso quotidiano

Non devi fare nulla: apri il progetto e usa `claude` o il pannello. `--continue` e `--resume`
ritrovano sempre le conversazioni del progetto, perché il progetto usa sempre lo stesso profilo.

- **Progetto nuovo?** Se `claude` risponde `nessun profilo associato`, fai `ccm bind <profilo>`
  (o usa la barra di stato di VS Code). È voluto: meglio un errore che l'account sbagliato.
- **Una volta sola con un altro account?** `ccm run <profilo>` (accetta gli stessi argomenti di `claude`).
- **Cambiare account a un progetto?** `ccm bind <altro-profilo>`. Vale per le sessioni nuove:
  quelle già aperte continuano con il profilo precedente.

## Comandi

| Comando | Cosa fa |
|---|---|
| `ccm add <nome> [--type team\|personal\|vertex] [--project ID] [--region R] [--gcloud-config N]` | crea un profilo con la sua config dir isolata |
| `ccm login <nome>` | primo login OAuth, o refresh delle credenziali gcloud per Vertex |
| `ccm bind <profilo> [dir]` | associa un progetto (default: root git, altrimenti cartella corrente) |
| `ccm unbind [dir]` | rimuove l'associazione |
| `ccm which [dir] [--json]` | profilo che verrebbe usato, e avvisi su settings del repo in conflitto |
| `ccm list [--json]` | profili e progetti associati |
| `ccm run <profilo> [argomenti]` | lancia claude con un profilo forzato |
| `ccm doctor` | verifica PATH, login, credenziali, associazioni orfane |
| `ccm edit <nome>` / `ccm remove <nome>` | modifica / elimina un profilo |

Variabili utili: `CCM_OVERRIDE=<profilo>` forza un profilo, `CCM_BYPASS=1` salta ccm,
`CCM_REAL_CLAUDE=/percorso/claude` indica il binario reale se non è nel PATH.

## Come funziona

- **Profili.** Ogni profilo è un file `~/.config/ccm/profiles/<nome>.env` (permessi 600) più
  una config dir in `~/.claude-accounts/<nome>`, passata a Claude Code tramite
  `CLAUDE_CONFIG_DIR`. Credenziali, impostazioni e conversazioni restano separate per account.
- **Associazioni.** Stanno in `~/.config/ccm/projects`, fuori dai repository: nessun nome di
  profilo finisce nei commit condivisi. Vince la regola con il percorso più lungo, e i percorsi
  sono risolti al percorso fisico (symlink compresi).
- **Shim.** `~/.local/share/ccm/shims/claude` viene prima del `claude` reale nel PATH. A ogni
  avvio trova il profilo della cartella corrente, **azzera** le variabili che potrebbero
  cambiare account, provider o progetto di billing (`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`,
  `CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CODE_USE_*`, `GOOGLE_CLOUD_PROJECT`, `GCLOUD_PROJECT`,
  `GOOGLE_APPLICATION_CREDENTIALS`…), applica il profilo e avvia il binario reale.
- **Pannello VS Code.** Con `claudeProcessWrapper`, l'estensione Claude Code chiama lo shim
  passandogli il proprio binario: lo shim applica il profilo e usa quel binario, così la
  versione resta allineata al pannello.
- **Fail-closed.** In una cartella non associata `claude` non parte. `--version`, `--help` e
  `update` funzionano ovunque.

## Conversazioni esistenti

Le conversazioni fatte **prima** di ccm stanno in `~/.claude/projects/` e ccm non le tocca.
Con un profilo nuovo però non le vedrai, perché ogni profilo ha la sua cartella. Due possibilità:

**Riusa `~/.claude` per un profilo.** Per il profilo dell'account con cui sei già loggato,
esegui `ccm edit <nome>` e imposta `CLAUDE_CONFIG_DIR=/Users/TUO-NOME-UTENTE/.claude`. Quel
profilo ritrova tutto com'era (e non serve rifare il login). Vale per un solo profilo.

**Copia le conversazioni di un progetto** nel profilo nuovo, a sessioni chiuse:

```bash
cd ~/work/piattaforma
enc=$(pwd -P | sed 's/[^A-Za-z0-9]/-/g')
ls -d ~/.claude/projects/"$enc"            # verifica che esista con questo nome
mkdir -p ~/.claude-accounts/vertex/projects
cp -R ~/.claude/projects/"$enc" ~/.claude-accounts/vertex/projects/
```

Alcune impostazioni per progetto (fiducia nella cartella, permessi accordati, server MCP
aggiunti con `claude mcp add` in scope locale) vanno ricreate nel profilo nuovo. Gli MCP
definiti nel `.mcp.json` del repository funzionano subito.

## Risoluzione dei problemi

**`ccm: comando non trovato` o `doctor` dice che lo shim non è il primo `claude`.**
Apri un nuovo terminale. Se persiste, il blocco `# >>> ccm >>>` deve essere l'**ultima** cosa
del tuo `~/.zshrc` / `~/.bashrc`: se lo segue qualcosa che modifica il PATH (per esempio
l'installer di Claude Code che aggiunge `~/.local/bin`), sposta il blocco in fondo.

**`nessun profilo associato a …`.** È il fail-closed: `ccm bind <profilo>` in quella cartella.
Attenzione ai *git worktree* creati fuori dalle cartelle associate: vanno associati a parte.

**`doctor` segnala variabili come `CLAUDE_CODE_USE_VERTEX` impostate nella shell.**
Sono residui di una configurazione precedente, di solito in `~/.zshrc`. Lo shim le ignora, ma
toglile: altrimenti tutto ciò che non passa da ccm (script, `CCM_BYPASS=1`) le userebbe.

**`? login non rilevato` su macOS.** Su macOS le credenziali stanno nel Portachiavi e ccm non
le vede: verifica con `/status` dentro Claude Code.

**Il pannello VS Code non risponde in un progetto.** Se la barra di stato è rossa il progetto
non è associato. Altrimenti esegui *ccm: Doctor* e controlla che `claudeCode.claudeProcessWrapper`
punti allo shim (*ccm: Configura pannello Claude Code*).

**Vertex fattura sul progetto sbagliato.** `GOOGLE_CLOUD_PROJECT`, `GCLOUD_PROJECT` e il file
in `GOOGLE_APPLICATION_CREDENTIALS` hanno priorità su `ANTHROPIC_VERTEX_PROJECT_ID`. Lo shim li
azzera; se ti servono, impostali esplicitamente nel file del profilo (`ccm edit vertex`).
Anche `.claude/settings.json` del repository può definire variabili: `ccm which` lo segnala.

**Più profili Vertex con identità GCP diverse.** Le credenziali ADC di gcloud sono per utente.
Imposta nel file di ciascun profilo un `CLOUDSDK_CONFIG` dedicato oppure un
`GOOGLE_APPLICATION_CREDENTIALS` con un service account.

## Limiti noti

- `CLAUDE_CONFIG_DIR` è molto usata ma non documentata ufficialmente. Dopo ogni aggiornamento
  di Claude Code esegui `ccm doctor` e verifica `/status`.
- Il modo in cui il pannello VS Code chiama `claudeProcessWrapper` (primo argomento = binario
  dell'estensione) è stato osservato, non documentato. Se cambia, lo shim ricade sul binario nel PATH.
- Con `CLAUDE_CONFIG_DIR` impostata alcune versioni di Claude Code leggono comunque anche
  `~/.claude/CLAUDE.md`: tieni lì solo istruzioni valide per tutti gli account.
- Il cambio di profilo vale per le sessioni nuove, non per quelle già aperte.
- Nei workspace multi-root il pannello usa il profilo della **prima** cartella.
- L'estensione ccm gestisce solo workspace locali (non SSH, container o WSL remoto).

## Aggiornare e disinstallare

**Aggiornare:** rilancia il comando di installazione (Opzione A) o `./install.sh` da una
versione nuova. Profili, associazioni e credenziali restano.

**Disinstallare:**

```bash
curl -fsSL https://raw.githubusercontent.com/FrancescoBoschi/claude-code-profiles/main/install.sh | bash -s -- --uninstall
```

Rimuove programma, blocco nei file rc ed estensione VS Code. Profili (`~/.config/ccm`) e
credenziali (`~/.claude-accounts`) restano: cancellali a mano se non servono più. Ricordati di
togliere `claudeCode.claudeProcessWrapper` dai settings di VS Code.

## Sviluppo

```text
bin/ccm              CLI
shims/claude         shim che sostituisce claude nel PATH
lib/ccm-common.sh    funzioni condivise
install.sh           installer / disinstaller
tests/smoke.sh       test della CLI
vscode/              estensione VS Code (JavaScript puro, nessun build step)
```

```bash
bash tests/smoke.sh && node vscode/test/run.js
```

Leggi [CONTRIBUTING.md](CONTRIBUTING.md) per le regole di compatibilità e per rilasciare una
versione.

## Licenza

[MIT](LICENSE)
