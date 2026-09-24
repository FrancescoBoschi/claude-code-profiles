// ccprof for VS Code: a thin UI on top of the "ccprof" CLI, which stays the single source of truth.
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
  const configured = vscode.workspace.getConfiguration('ccprof').get('path');
  if (configured) return configured.replace(/^~(?=\/|$)/, os.homedir());
  const def = path.join(os.homedir(), '.local', 'share', 'ccprof', 'bin', 'ccprof');
  return fs.existsSync(def) ? def : 'ccprof';
}

function run(args, cwd) {
  return new Promise((resolve, reject) => {
    const env = { ...process.env };
    delete env.CCPROF_OVERRIDE;
    delete env.CCPROF_BYPASS;
    cp.execFile(ccmPath(), args, { cwd: cwd || os.homedir(), env, timeout: 30000, maxBuffer: 4 * 1024 * 1024 },
      (err, stdout, stderr) => {
        if (err && err.code === 'ENOENT') {
          return reject(new Error('ccprof not found: install it, or set "ccprof.path" in your settings'));
        }
        const code = err ? (typeof err.code === 'number' ? err.code : 1) : 0;
        resolve({ code, stdout: String(stdout), stderr: String(stderr) });
      });
  });
}

async function runJson(args) {
  const r = await run(args);
  if (r.code !== 0) throw new Error(r.stderr.trim() || `ccprof ${args.join(' ')}: exit code ${r.code}`);
  return JSON.parse(r.stdout);
}

async function runOrThrow(args) {
  const r = await run(args);
  if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim() || `ccprof ${args.join(' ')} failed`);
  return r.stdout.trim();
}

// ---------------------------------------------------------------- helpers

function fileFolders() {
  return (vscode.workspace.workspaceFolders || []).filter(f => f.uri.scheme === 'file');
}

function tilde(p) {
  const h = os.homedir();
  return p && (p === h || p.startsWith(h + '/')) ? '~' + p.slice(h.length) : p;
}

function describe(info) {
  if (!info.profile) return 'no profile';
  if (!info.exists) return `${info.profile} (missing profile)`;
  return info.kind === 'vertex' ? `${info.profile} · vertex ${info.vertexProject || ''}`.trim() : `${info.profile} · ${info.kind}`;
}

async function pickFolder(placeHolder) {
  const folders = fileFolders();
  if (!folders.length) {
    vscode.window.showErrorMessage('ccprof: open a project folder first.');
    return undefined;
  }
  if (folders.length === 1) return folders[0];
  const pick = await vscode.window.showQuickPick(
    folders.map((f, i) => ({ label: f.name, description: tilde(f.uri.fsPath) + (i === 0 ? '  (decides the panel profile)' : ''), folder: f })),
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
  if (allowNew) items.push({ label: '$(add) New profile…', description: 'opens a terminal with "ccprof add"', create: true });
  const pick = await vscode.window.showQuickPick(items, { placeHolder });
  if (pick && pick.create) {
    const t = vscode.window.createTerminal({ name: 'ccprof add' });
    t.show();
    t.sendText('ccprof add ', false);
    return undefined;
  }
  return pick && pick.profile;
}

function scheduleRefresh() {
  clearTimeout(refreshTimer);
  refreshTimer = setTimeout(() => refresh().catch(() => {}), 300);
}

// ---------------------------------------------------------------- status bar

async function refresh() {
  const folders = fileFolders();
  if (!folders.length) { status.hide(); return; }
  let infos;
  try {
    infos = await Promise.all(folders.map(async f => ({ folder: f, info: await runJson(['which', '--json', f.uri.fsPath]) })));
  } catch (e) {
    status.text = '$(warning) ccprof';
    status.tooltip = e.message;
    status.backgroundColor = new vscode.ThemeColor('statusBarItem.errorBackground');
    status.show();
    return;
  }

  const main = infos[0].info;
  const mixed = new Set(infos.map(i => i.info.profile || '')).size > 1;
  const highlight = vscode.workspace.getConfiguration('ccprof').get('highlightPersonal', true);

  if (!main.profile || !main.exists) {
    status.text = `$(circle-slash) ccprof: ${main.profile ? main.profile + '?' : 'no profile'}`;
    status.backgroundColor = new vscode.ThemeColor('statusBarItem.errorBackground');
  } else {
    status.text = `$(account) ccprof: ${main.profile}` + (main.kind === 'vertex' && main.vertexProject ? ` · ${main.vertexProject}` : '');
    status.backgroundColor = main.kind === 'personal' && highlight
      ? new vscode.ThemeColor('statusBarItem.warningBackground') : undefined;
  }
  if (mixed || main.conflictingSettings.length) status.text += ' $(warning)';

  const md = new vscode.MarkdownString(undefined, true);
  md.appendMarkdown('**ccprof — Claude Code profile**\n\n');
  for (const { folder, info } of infos) {
    md.appendMarkdown(`- **${folder.name}**: ${describe(info)}`);
    if (info.source === 'bind' && info.boundPath !== info.dir) md.appendMarkdown(` _(from ${tilde(info.boundPath)})_`);
    md.appendMarkdown('\n');
    for (const w of info.conflictingSettings) md.appendMarkdown(`  - $(warning) ${tilde(w)} sets account/provider variables\n`);
  }
  if (!main.profile) md.appendMarkdown('\nThe panel and `claude` will not start here until you bind a profile.\n');
  if (mixed) md.appendMarkdown('\n$(warning) Folders use different profiles: the panel uses the one of the **first** folder.\n');
  md.appendMarkdown('\n_Click for actions_');
  status.tooltip = md;
  status.show();
}

// ---------------------------------------------------------------- commands

async function cmdBind() {
  const folder = await pickFolder('Which folder do you want to bind?');
  if (!folder) return;
  const target = folder.uri.fsPath;
  const info = await runJson(['which', '--json', target]);
  const profile = await pickProfile(`Profile for ${folder.name}`, info.profile, true);
  if (!profile) return;

  const parent = path.dirname(target);
  const scope = await vscode.window.showQuickPick([
    { label: folder.name, description: tilde(target), detail: 'Only this project', path: target },
    { label: path.basename(parent), description: tilde(parent), detail: 'Every project in this folder, including future ones', path: parent },
  ], { placeHolder: `Where should "${profile}" apply?` });
  if (!scope) return;

  if (info.profile && info.exists && info.profile !== profile) {
    const ok = await vscode.window.showWarningMessage(
      `Switching from "${info.profile}" to "${profile}". Existing conversations stay in the "${info.profile}" profile and will not be visible from "${profile}".`,
      { modal: true }, 'Continue');
    if (ok !== 'Continue') return;
  }
  await runOrThrow(['bind', profile, scope.path]);
  await refresh();
  const choice = await vscode.window.showInformationMessage(
    `ccprof: ${tilde(scope.path)} → ${profile}. New Claude sessions will use this profile; sessions already open keep the previous one.`,
    'Reload Window');
  if (choice) vscode.commands.executeCommand('workbench.action.reloadWindow');
}

async function cmdUnbind() {
  const folder = await pickFolder('Which folder do you want to unbind?');
  if (!folder) return;
  const info = await runJson(['which', '--json', folder.uri.fsPath]);
  if (info.source !== 'bind') {
    vscode.window.showInformationMessage(`ccprof: ${folder.name} has no binding.`);
    return;
  }
  let target = info.boundPath;
  if (info.boundPath !== info.dir) {
    const ok = await vscode.window.showWarningMessage(
      `The "${info.profile}" profile is inherited from ${tilde(info.boundPath)}. Removing that binding affects every project inside it.`,
      { modal: true }, 'Remove Anyway');
    if (ok !== 'Remove Anyway') return;
  }
  await runOrThrow(['unbind', target]);
  await refresh();
  vscode.window.showInformationMessage(`ccprof: binding removed from ${tilde(target)}.`);
}

async function cmdOpenTerminal() {
  const folder = await pickFolder('Which folder should Claude open in?');
  if (!folder) return;
  const info = await runJson(['which', '--json', folder.uri.fsPath]);
  const profile = await pickProfile('Which profile?', info.profile, false);
  if (!profile) return;
  const env = profile !== info.profile ? { CCPROF_OVERRIDE: profile } : undefined;
  const t = vscode.window.createTerminal({ name: `Claude · ${profile}`, cwd: folder.uri, env });
  t.show();
  t.sendText('claude');
}

async function showInOutput(title, args) {
  output.clear();
  output.appendLine(`$ ccprof ${args.join(' ')}`);
  output.show(true);
  const r = await run(args);
  output.append(r.stdout);
  if (r.stderr) output.append(r.stderr);
  output.appendLine('');
  output.appendLine(`— ${title}: ${r.code === 0 ? 'ok' : 'needs attention (exit code ' + r.code + ')'}`);
}

async function checkPanelWrapper(interactive) {
  const list = await runJson(['list', '--json']);
  const conf = vscode.workspace.getConfiguration('claudeCode');
  const current = conf.get('claudeProcessWrapper');
  if (current === list.shim) {
    if (interactive) vscode.window.showInformationMessage('ccprof: the Claude Code panel already goes through ccprof.');
    return;
  }
  if (!interactive && ctx.globalState.get('ccprof.skipWrapperCheck')) return;
  const msg = current
    ? `ccprof: the Claude Code panel uses another wrapper (${current}) and does not apply ccprof profiles.`
    : 'ccprof: the Claude Code panel does not go through ccprof and would use the default account.';
  const buttons = interactive ? ['Configure'] : ['Configure', 'Don\'t Ask Again'];
  const choice = await vscode.window.showWarningMessage(msg, ...buttons);
  if (choice === 'Configure') {
    await conf.update('claudeProcessWrapper', list.shim, vscode.ConfigurationTarget.Global);
    const r = await vscode.window.showInformationMessage('ccprof: panel configured. Reload the window to apply it.', 'Reload Window');
    if (r) vscode.commands.executeCommand('workbench.action.reloadWindow');
  } else if (choice === 'Don\'t Ask Again') {
    await ctx.globalState.update('ccprof.skipWrapperCheck', true);
  }
}

async function cmdMenu() {
  const pick = await vscode.window.showQuickPick([
    { label: '$(link) Bind Profile to Workspace', cmd: 'ccprof.bind' },
    { label: '$(debug-disconnect) Remove Binding', cmd: 'ccprof.unbind' },
    { label: '$(terminal) Open Claude Terminal with Profile…', cmd: 'ccprof.openTerminal' },
    { label: '$(list-unordered) Show Profiles and Projects', cmd: 'ccprof.list' },
    { label: '$(pulse) Doctor', cmd: 'ccprof.doctor' },
    { label: '$(gear) Configure Claude Code Panel', cmd: 'ccprof.configurePanel' },
  ], { placeHolder: 'ccprof' });
  if (pick) vscode.commands.executeCommand(pick.cmd);
}

function guarded(fn) {
  return async (...args) => {
    try { await fn(...args); } catch (e) { vscode.window.showErrorMessage(`ccprof: ${e.message}`); }
  };
}

// ---------------------------------------------------------------- lifecycle

async function watchConfig() {
  try {
    const list = await runJson(['list', '--json']);
    if (watcher) watcher.close();
    watcher = fs.watch(list.home, () => scheduleRefresh());
  } catch (_) { /* without a watcher we still refresh when the window gets focus */ }
}

function activate(context) {
  ctx = context;
  output = vscode.window.createOutputChannel('ccprof');
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  status.command = 'ccprof.menu';
  status.name = 'ccprof — Claude Code profile';

  const reg = (id, fn) => context.subscriptions.push(vscode.commands.registerCommand(id, guarded(fn)));
  reg('ccprof.menu', cmdMenu);
  reg('ccprof.bind', cmdBind);
  reg('ccprof.unbind', cmdUnbind);
  reg('ccprof.openTerminal', cmdOpenTerminal);
  reg('ccprof.list', () => showInOutput('Profiles and projects', ['list']));
  reg('ccprof.doctor', () => showInOutput('Doctor', ['doctor']));
  reg('ccprof.configurePanel', () => checkPanelWrapper(true));
  reg('ccprof.refresh', refresh);

  context.subscriptions.push(
    status, output,
    vscode.workspace.onDidChangeWorkspaceFolders(scheduleRefresh),
    vscode.window.onDidChangeWindowState(s => { if (s.focused) scheduleRefresh(); }),
    vscode.workspace.onDidChangeConfiguration(e => { if (e.affectsConfiguration('ccprof')) scheduleRefresh(); }),
    { dispose: () => { if (watcher) watcher.close(); clearTimeout(refreshTimer); } },
  );

  refresh().catch(() => {});
  watchConfig();
  if (vscode.workspace.getConfiguration('ccprof').get('checkClaudeWrapper', true)) {
    checkPanelWrapper(false).catch(() => {});
  }
}

function deactivate() {}

module.exports = { activate, deactivate };
