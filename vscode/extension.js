// ccm per VS Code: interfaccia sottile sopra la CLI "ccm", che resta l'unica fonte di verità.
'use strict';
const vscode = require('vscode');
const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

let status;
let output;
let ctx;
let refreshTimer;
let watcher;

// ---------------------------------------------------------------- CLI

function ccmPath() {
  const configured = vscode.workspace.getConfiguration('ccm').get('path');
  if (configured) return configured.replace(/^~(?=\/|$)/, os.homedir());
  const def = path.join(os.homedir(), '.local', 'share', 'ccm', 'bin', 'ccm');
  return fs.existsSync(def) ? def : 'ccm';
}

function run(args, cwd) {
  return new Promise((resolve, reject) => {
    const env = { ...process.env };
    delete env.CCM_OVERRIDE;
    delete env.CCM_BYPASS;
    cp.execFile(ccmPath(), args, { cwd: cwd || os.homedir(), env, timeout: 30000, maxBuffer: 4 * 1024 * 1024 },
      (err, stdout, stderr) => {
        if (err && err.code === 'ENOENT') {
          return reject(new Error('ccm non trovato: installalo oppure imposta "ccm.path" nei settings'));
        }
        const code = err ? (typeof err.code === 'number' ? err.code : 1) : 0;
        resolve({ code, stdout: String(stdout), stderr: String(stderr) });
      });
  });
}

async function runJson(args) {
  const r = await run(args);
  if (r.code !== 0) throw new Error(r.stderr.trim() || `ccm ${args.join(' ')}: codice di uscita ${r.code}`);
  return JSON.parse(r.stdout);
}

async function runOrThrow(args) {
  const r = await run(args);
  if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim() || `ccm ${args.join(' ')} non riuscito`);
  return r.stdout.trim();
}

// ---------------------------------------------------------------- utilità

function fileFolders() {
  return (vscode.workspace.workspaceFolders || []).filter(f => f.uri.scheme === 'file');
}

function tilde(p) {
  const h = os.homedir();
  return p && (p === h || p.startsWith(h + '/')) ? '~' + p.slice(h.length) : p;
}

function describe(info) {
  if (!info.profile) return 'nessun profilo';
  if (!info.exists) return `${info.profile} (profilo inesistente)`;
  return info.kind === 'vertex' ? `${info.profile} · vertex ${info.vertexProject || ''}`.trim() : `${info.profile} · ${info.kind}`;
}

async function pickFolder(placeHolder) {
  const folders = fileFolders();
  if (!folders.length) {
    vscode.window.showErrorMessage('ccm: apri prima una cartella di progetto.');
    return undefined;
  }
  if (folders.length === 1) return folders[0];
  const pick = await vscode.window.showQuickPick(
    folders.map((f, i) => ({ label: f.name, description: tilde(f.uri.fsPath) + (i === 0 ? '  (decide il profilo del pannello)' : ''), folder: f })),
    { placeHolder });
  return pick && pick.folder;
}

async function pickProfile(placeHolder, current, allowNew) {
  const list = await runJson(['list', '--json']);
  const items = list.profiles.map(p => ({
    label: (p.name === current ? '$(check) ' : '') + p.name,
    description: p.kind === 'vertex' ? `vertex · ${p.vertexProject || ''}` : p.kind,
    detail: tilde(p.configDir),
    profile: p.name,
  }));
  if (allowNew) items.push({ label: '$(add) Nuovo profilo…', description: 'apre un terminale con "ccm add"', create: true });
  const pick = await vscode.window.showQuickPick(items, { placeHolder });
  if (pick && pick.create) {
    const t = vscode.window.createTerminal({ name: 'ccm add' });
    t.show();
    t.sendText('ccm add ', false);
    return undefined;
  }
  return pick && pick.profile;
}

function scheduleRefresh() {
  clearTimeout(refreshTimer);
  refreshTimer = setTimeout(() => refresh().catch(() => {}), 300);
}

// ---------------------------------------------------------------- barra di stato

async function refresh() {
  const folders = fileFolders();
  if (!folders.length) { status.hide(); return; }
  let infos;
  try {
    infos = await Promise.all(folders.map(async f => ({ folder: f, info: await runJson(['which', '--json', f.uri.fsPath]) })));
  } catch (e) {
    status.text = '$(warning) ccm';
    status.tooltip = e.message;
    status.backgroundColor = new vscode.ThemeColor('statusBarItem.errorBackground');
    status.show();
    return;
  }

  const main = infos[0].info;
  const mixed = new Set(infos.map(i => i.info.profile || '')).size > 1;
  const highlight = vscode.workspace.getConfiguration('ccm').get('highlightPersonal', true);

  if (!main.profile || !main.exists) {
    status.text = `$(circle-slash) ccm: ${main.profile ? main.profile + '?' : 'nessun profilo'}`;
    status.backgroundColor = new vscode.ThemeColor('statusBarItem.errorBackground');
  } else {
    status.text = `$(account) ccm: ${main.profile}` + (main.kind === 'vertex' && main.vertexProject ? ` · ${main.vertexProject}` : '');
    status.backgroundColor = main.kind === 'personal' && highlight
      ? new vscode.ThemeColor('statusBarItem.warningBackground') : undefined;
  }
  if (mixed || main.conflictingSettings.length) status.text += ' $(warning)';

  const md = new vscode.MarkdownString(undefined, true);
  md.appendMarkdown('**ccm — profilo Claude Code**\n\n');
  for (const { folder, info } of infos) {
    md.appendMarkdown(`- **${folder.name}**: ${describe(info)}`);
    if (info.source === 'bind' && info.boundPath !== info.dir) md.appendMarkdown(` _(da ${tilde(info.boundPath)})_`);
    md.appendMarkdown('\n');
    for (const w of info.conflictingSettings) md.appendMarkdown(`  - $(warning) ${tilde(w)} imposta variabili di account/provider\n`);
  }
  if (!main.profile) md.appendMarkdown('\nIl pannello e `claude` non partiranno qui finché non associ un profilo.\n');
  if (mixed) md.appendMarkdown('\n$(warning) Cartelle con profili diversi: il pannello usa quello della **prima** cartella.\n');
  md.appendMarkdown('\n_Clic per le azioni_');
  status.tooltip = md;
  status.show();
}

// ---------------------------------------------------------------- comandi

async function cmdBind() {
  const folder = await pickFolder('Quale cartella vuoi associare?');
  if (!folder) return;
  const target = folder.uri.fsPath;
  const info = await runJson(['which', '--json', target]);
  const profile = await pickProfile(`Profilo per ${folder.name}`, info.profile, true);
  if (!profile) return;

  const parent = path.dirname(target);
  const scope = await vscode.window.showQuickPick([
    { label: folder.name, description: tilde(target), detail: 'Solo questo progetto', path: target },
    { label: path.basename(parent), description: tilde(parent), detail: 'Tutti i progetti in questa cartella, anche quelli futuri', path: parent },
  ], { placeHolder: `Dove applicare "${profile}"?` });
  if (!scope) return;

  if (info.profile && info.exists && info.profile !== profile) {
    const ok = await vscode.window.showWarningMessage(
      `Passi da "${info.profile}" a "${profile}". Le conversazioni già fatte restano nel profilo "${info.profile}" e non saranno visibili con "${profile}".`,
      { modal: true }, 'Continua');
    if (ok !== 'Continua') return;
  }
  await runOrThrow(['bind', profile, scope.path]);
  await refresh();
  const choice = await vscode.window.showInformationMessage(
    `ccm: ${tilde(scope.path)} → ${profile}. Le nuove sessioni Claude useranno questo profilo; quelle già aperte continuano con il precedente.`,
    'Ricarica finestra');
  if (choice) vscode.commands.executeCommand('workbench.action.reloadWindow');
}

async function cmdUnbind() {
  const folder = await pickFolder('Da quale cartella vuoi rimuovere l\'associazione?');
  if (!folder) return;
  const info = await runJson(['which', '--json', folder.uri.fsPath]);
  if (info.source !== 'bind') {
    vscode.window.showInformationMessage(`ccm: ${folder.name} non ha associazioni.`);
    return;
  }
  let target = info.boundPath;
  if (info.boundPath !== info.dir) {
    const ok = await vscode.window.showWarningMessage(
      `Il profilo "${info.profile}" è ereditato da ${tilde(info.boundPath)}. Rimuovere quell'associazione vale per tutti i progetti al suo interno.`,
      { modal: true }, 'Rimuovi comunque');
    if (ok !== 'Rimuovi comunque') return;
  }
  await runOrThrow(['unbind', target]);
  await refresh();
  vscode.window.showInformationMessage(`ccm: associazione rimossa da ${tilde(target)}.`);
}

async function cmdOpenTerminal() {
  const folder = await pickFolder('In quale cartella aprire Claude?');
  if (!folder) return;
  const info = await runJson(['which', '--json', folder.uri.fsPath]);
  const profile = await pickProfile('Con quale profilo?', info.profile, false);
  if (!profile) return;
  const env = profile !== info.profile ? { CCM_OVERRIDE: profile } : undefined;
  const t = vscode.window.createTerminal({ name: `Claude · ${profile}`, cwd: folder.uri, env });
  t.show();
  t.sendText('claude');
}

async function showInOutput(title, args) {
  output.clear();
  output.appendLine(`$ ccm ${args.join(' ')}`);
  output.show(true);
  const r = await run(args);
  output.append(r.stdout);
  if (r.stderr) output.append(r.stderr);
  output.appendLine('');
  output.appendLine(`— ${title}: ${r.code === 0 ? 'ok' : 'da verificare (codice ' + r.code + ')'}`);
}

async function checkPanelWrapper(interactive) {
  const list = await runJson(['list', '--json']);
  const conf = vscode.workspace.getConfiguration('claudeCode');
  const current = conf.get('claudeProcessWrapper');
  if (current === list.shim) {
    if (interactive) vscode.window.showInformationMessage('ccm: il pannello Claude Code passa già da ccm.');
    return;
  }
  if (!interactive && ctx.globalState.get('ccm.skipWrapperCheck')) return;
  const msg = current
    ? `ccm: il pannello Claude Code usa un altro wrapper (${current}) e non applica i profili ccm.`
    : 'ccm: il pannello Claude Code non passa da ccm e userebbe l\'account di default.';
  const buttons = interactive ? ['Configura'] : ['Configura', 'Non chiedere più'];
  const choice = await vscode.window.showWarningMessage(msg, ...buttons);
  if (choice === 'Configura') {
    await conf.update('claudeProcessWrapper', list.shim, vscode.ConfigurationTarget.Global);
    const r = await vscode.window.showInformationMessage('ccm: pannello configurato. Ricarica la finestra per applicarlo.', 'Ricarica finestra');
    if (r) vscode.commands.executeCommand('workbench.action.reloadWindow');
  } else if (choice === 'Non chiedere più') {
    await ctx.globalState.update('ccm.skipWrapperCheck', true);
  }
}

async function cmdMenu() {
  const pick = await vscode.window.showQuickPick([
    { label: '$(link) Associa profilo al workspace', cmd: 'ccm.bind' },
    { label: '$(debug-disconnect) Rimuovi associazione', cmd: 'ccm.unbind' },
    { label: '$(terminal) Apri terminale Claude con profilo…', cmd: 'ccm.openTerminal' },
    { label: '$(list-unordered) Mostra profili e progetti', cmd: 'ccm.list' },
    { label: '$(pulse) Doctor', cmd: 'ccm.doctor' },
    { label: '$(gear) Configura pannello Claude Code', cmd: 'ccm.configurePanel' },
  ], { placeHolder: 'ccm' });
  if (pick) vscode.commands.executeCommand(pick.cmd);
}

function guarded(fn) {
  return async (...args) => {
    try { await fn(...args); } catch (e) { vscode.window.showErrorMessage(`ccm: ${e.message}`); }
  };
}

// ---------------------------------------------------------------- ciclo di vita

async function watchConfig() {
  try {
    const list = await runJson(['list', '--json']);
    if (watcher) watcher.close();
    watcher = fs.watch(list.home, () => scheduleRefresh());
  } catch (_) { /* senza watcher si aggiorna comunque al focus della finestra */ }
}

function activate(context) {
  ctx = context;
  output = vscode.window.createOutputChannel('ccm');
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  status.command = 'ccm.menu';
  status.name = 'ccm — profilo Claude Code';

  const reg = (id, fn) => context.subscriptions.push(vscode.commands.registerCommand(id, guarded(fn)));
  reg('ccm.menu', cmdMenu);
  reg('ccm.bind', cmdBind);
  reg('ccm.unbind', cmdUnbind);
  reg('ccm.openTerminal', cmdOpenTerminal);
  reg('ccm.list', () => showInOutput('Profili e progetti', ['list']));
  reg('ccm.doctor', () => showInOutput('Doctor', ['doctor']));
  reg('ccm.configurePanel', () => checkPanelWrapper(true));
  reg('ccm.refresh', refresh);

  context.subscriptions.push(
    status, output,
    vscode.workspace.onDidChangeWorkspaceFolders(scheduleRefresh),
    vscode.window.onDidChangeWindowState(s => { if (s.focused) scheduleRefresh(); }),
    vscode.workspace.onDidChangeConfiguration(e => { if (e.affectsConfiguration('ccm')) scheduleRefresh(); }),
    { dispose: () => { if (watcher) watcher.close(); clearTimeout(refreshTimer); } },
  );

  refresh().catch(() => {});
  watchConfig();
  if (vscode.workspace.getConfiguration('ccm').get('checkClaudeWrapper', true)) {
    checkPanelWrapper(false).catch(() => {});
  }
}

function deactivate() {}

module.exports = { activate, deactivate };
