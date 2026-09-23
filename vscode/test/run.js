// Test dell'estensione: API "vscode" simulata + ccm reale installato in un HOME temporaneo.
// Uso: node vscode/test/run.js   (dalla root del pacchetto ccm)
'use strict';
const Module = require('module');
const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const assert = require('assert');

const ROOT = path.resolve(__dirname, '..', '..');
const T = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'ccmx-')));
const HOME = path.join(T, 'home');
fs.mkdirSync(HOME, { recursive: true });
fs.writeFileSync(path.join(HOME, '.bashrc'), '');
process.env.HOME = HOME;
delete process.env.XDG_CONFIG_HOME;
delete process.env.CCM_HOME;
const sh = (c, cwd) => cp.execFileSync('bash', ['-c', c], { cwd: cwd || HOME, env: process.env, encoding: 'utf8' });

sh(`bash "${ROOT}/install.sh" >/dev/null`);
const CCM = path.join(HOME, '.local/share/ccm/bin/ccm');
const W = path.join(T, 'work');
for (const d of ['Work Repos/api', 'Work Repos/ui', 'Personal/side-project', 'libero']) fs.mkdirSync(path.join(W, d), { recursive: true });
sh(`"${CCM}" add team --type team >/dev/null && "${CCM}" add mio --type personal >/dev/null && "${CCM}" add vertex --type vertex --project acme-bill --region global >/dev/null`);
sh(`"${CCM}" bind team "${W}/Work Repos" >/dev/null && "${CCM}" bind mio "${W}/Personal/side-project" >/dev/null`);

// ------------------------------------------------------------ stub vscode
const state = { picks: [], warnings: [], infos: [], errors: [], terminals: [], executed: [], config: {}, folders: [] };
const nextPick = () => state.picks.shift();
class ThemeColor { constructor(id) { this.id = id; } }
class MarkdownString { constructor() { this.value = ''; } appendMarkdown(s) { this.value += s; return this; } }
const statusItem = { text: '', show() { this.visible = true; }, hide() { this.visible = false; }, dispose() {} };
const commands = {};
const ev = () => ({ dispose() {} });
const vscode = {
  ThemeColor, MarkdownString,
  StatusBarAlignment: { Left: 1 },
  ConfigurationTarget: { Global: 1 },
  Uri: { file: p => ({ scheme: 'file', fsPath: p }) },
  window: {
    createStatusBarItem: () => statusItem,
    createOutputChannel: () => ({ lines: [], clear() { this.lines = []; }, append(s) { this.lines.push(s); }, appendLine(s) { this.lines.push(s + '\n'); }, show() {}, dispose() {} }),
    showQuickPick: async (items) => {
      const want = nextPick();
      if (want === undefined) return undefined;
      const found = items.find(i => i.label.includes(want) || i.profile === want);
      assert(found, `voce "${want}" non trovata tra: ${items.map(i => i.label).join(' | ')}`);
      return found;
    },
    showWarningMessage: async (msg, ...rest) => { state.warnings.push(msg); const b = rest.filter(x => typeof x === 'string'); return state.warnAnswer === undefined ? b[0] : state.warnAnswer; },
    showInformationMessage: async (msg) => { state.infos.push(msg); return undefined; },
    showErrorMessage: async (msg) => { state.errors.push(msg); },
    createTerminal: (o) => { const t = { opts: o, sent: [], show() {}, sendText(s) { this.sent.push(s); } }; state.terminals.push(t); return t; },
    onDidChangeWindowState: ev,
  },
  workspace: {
    get workspaceFolders() { return state.folders; },
    getConfiguration: (sec) => ({
      get: (k, d) => (state.config[`${sec}.${k}`] !== undefined ? state.config[`${sec}.${k}`] : d),
      update: async (k, v) => { state.config[`${sec}.${k}`] = v; },
    }),
    onDidChangeWorkspaceFolders: ev,
    onDidChangeConfiguration: ev,
  },
  commands: {
    registerCommand: (id, fn) => { commands[id] = fn; return { dispose() {} }; },
    executeCommand: async (id) => { state.executed.push(id); },
  },
};
const origLoad = Module._load;
Module._load = function (req, ...a) { return req === 'vscode' ? vscode : origLoad.call(this, req, ...a); };

const folder = (rel) => ({ name: path.basename(rel), uri: vscode.Uri.file(path.join(W, rel)) });
const wait = (ms) => new Promise(r => setTimeout(r, ms));
const ext = require(path.join(ROOT, 'vscode', 'extension.js'));
const globalState = { m: {}, get(k) { return this.m[k]; }, async update(k, v) { this.m[k] = v; } };
const projects = () => fs.readFileSync(path.join(HOME, '.config/ccm/projects'), 'utf8');

let pass = 0, fail = 0;
async function test(name, fn) {
  try { await fn(); pass++; console.log('  ok   ' + name); }
  catch (e) { fail++; console.log('  FAIL ' + name + '\n       ' + e.message); }
}

(async () => {
  state.folders = [folder('Work Repos/api'), folder('Work Repos/ui')];
  state.warnAnswer = 'Non chiedere più';
  ext.activate({ subscriptions: [], globalState });
  await wait(1500);

  await test('barra di stato: profilo ereditato dalla cartella contenitore', () => {
    assert.strictEqual(statusItem.text, '$(account) ccm: team');
    assert(statusItem.tooltip.value.includes('(da '), statusItem.tooltip.value);
  });
  await test('avviso all\'avvio se il pannello non passa da ccm', () => {
    assert(state.warnings.some(w => w.includes('pannello Claude Code non passa da ccm')));
    assert.strictEqual(globalState.get('ccm.skipWrapperCheck'), true);
  });

  await test('configura pannello imposta claudeProcessWrapper sullo shim', async () => {
    state.warnAnswer = undefined;
    await commands['ccm.configurePanel']();
    assert.strictEqual(state.config['claudeCode.claudeProcessWrapper'], path.join(HOME, '.local/share/ccm/shims/claude'));
  });

  await test('workspace non associato → rosso', async () => {
    state.folders = [folder('libero')];
    await commands['ccm.refresh']();
    assert(statusItem.text.includes('nessun profilo'));
    assert.strictEqual(statusItem.backgroundColor.id, 'statusBarItem.errorBackground');
  });

  await test('associa: profilo vertex solo al progetto', async () => {
    state.picks = ['vertex', 'libero'];
    await commands['ccm.bind']();
    assert(projects().includes(`${W}/libero\tvertex`), projects());
    assert.strictEqual(statusItem.text, '$(account) ccm: vertex · acme-bill');
  });

  await test('cambio profilo chiede conferma e avvisa per le conversazioni', async () => {
    state.warnings = [];
    state.warnAnswer = 'Continua';
    state.picks = ['mio', 'libero'];
    await commands['ccm.bind']();
    assert(state.warnings.some(w => w.includes('conversazioni')));
    assert(projects().includes(`${W}/libero\tmio`));
    assert.strictEqual(statusItem.backgroundColor.id, 'statusBarItem.warningBackground');
  });

  await test('annullando la conferma non cambia nulla', async () => {
    state.warnAnswer = null;
    state.picks = ['team', 'libero'];
    await commands['ccm.bind']();
    assert(projects().includes(`${W}/libero\tmio`));
  });

  await test('multi-root con profili diversi → avviso', async () => {
    state.folders = [folder('Work Repos/api'), folder('Personal/side-project')];
    await commands['ccm.refresh']();
    assert(statusItem.text.endsWith('$(warning)'));
    assert(statusItem.tooltip.value.includes('prima'));
  });

  await test('terminale con profilo diverso usa CCM_OVERRIDE', async () => {
    state.folders = [folder('libero')];
    state.picks = ['vertex'];
    await commands['ccm.openTerminal']();
    const t = state.terminals.pop();
    assert.deepStrictEqual(t.opts.env, { CCM_OVERRIDE: 'vertex' });
    assert.deepStrictEqual(t.sent, ['claude']);
  });

  await test('rimuovi associazione ereditata chiede conferma', async () => {
    state.folders = [folder('Work Repos/ui')];
    state.warnings = [];
    state.warnAnswer = 'Rimuovi comunque';
    await commands['ccm.unbind']();
    assert(state.warnings.some(w => w.includes('ereditato')));
    assert(!projects().includes('Work Repos\tteam'));
  });

  await test('ccm assente → errore leggibile', async () => {
    state.config['ccm.path'] = '/non/esiste/ccm';
    state.errors = [];
    await commands['ccm.bind']();
    assert(state.errors.some(e => e.includes('ccm non trovato')), state.errors.join());
    delete state.config['ccm.path'];
  });

  console.log(`\nRisultato: ${pass} ok, ${fail} falliti`);
  fs.rmSync(T, { recursive: true, force: true });
  process.exit(fail ? 1 : 0);
})();
