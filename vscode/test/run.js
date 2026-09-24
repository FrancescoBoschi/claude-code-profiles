// Extension test: simulated "vscode" API + real ccprof installed in a temporary HOME.
// Usage: node vscode/test/run.js   (from the repository root)
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
delete process.env.CCPROF_HOME;
const sh = (c, cwd) => cp.execFileSync('bash', ['-c', c], { cwd: cwd || HOME, env: process.env, encoding: 'utf8' });

sh(`bash "${ROOT}/install.sh" >/dev/null`);
const CCM = path.join(HOME, '.local/share/ccprof/bin/ccprof');
const W = path.join(T, 'work');
for (const d of ['Work Repos/api', 'Work Repos/ui', 'Personal/side-project', 'free']) fs.mkdirSync(path.join(W, d), { recursive: true });
sh(`"${CCM}" add work --type team >/dev/null && "${CCM}" add personal --type personal >/dev/null && "${CCM}" add gcp --type vertex --project acme-bill --region global >/dev/null`);
sh(`"${CCM}" bind work "${W}/Work Repos" >/dev/null && "${CCM}" bind personal "${W}/Personal/side-project" >/dev/null`);

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
      assert(found, `item "${want}" not found among: ${items.map(i => i.label).join(' | ')}`);
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
const projects = () => fs.readFileSync(path.join(HOME, '.config/ccprof/projects'), 'utf8');

let pass = 0, fail = 0;
async function test(name, fn) {
  try { await fn(); pass++; console.log('  ok   ' + name); }
  catch (e) { fail++; console.log('  FAIL ' + name + '\n       ' + e.message); }
}

(async () => {
  state.folders = [folder('Work Repos/api'), folder('Work Repos/ui')];
  state.warnAnswer = 'Don\'t Ask Again';
  ext.activate({ subscriptions: [], globalState });
  await wait(1500);

  await test('status bar: profile inherited from the parent folder', () => {
    assert.strictEqual(statusItem.text, '$(account) ccprof: work');
    assert(statusItem.tooltip.value.includes('(from '), statusItem.tooltip.value);
  });
  await test('startup warning when the panel does not go through ccprof', () => {
    assert(state.warnings.some(w => w.includes('panel does not go through ccprof')));
    assert.strictEqual(globalState.get('ccprof.skipWrapperCheck'), true);
  });

  await test('configure panel sets claudeProcessWrapper to the shim', async () => {
    state.warnAnswer = undefined;
    await commands['ccprof.configurePanel']();
    assert.strictEqual(state.config['claudeCode.claudeProcessWrapper'], path.join(HOME, '.local/share/ccprof/shims/claude'));
  });

  await test('unbound workspace → red', async () => {
    state.folders = [folder('free')];
    await commands['ccprof.refresh']();
    assert(statusItem.text.includes('no profile'));
    assert.strictEqual(statusItem.backgroundColor.id, 'statusBarItem.errorBackground');
  });

  await test('bind: vertex profile to this project only', async () => {
    state.picks = ['gcp', 'free'];
    await commands['ccprof.bind']();
    assert(projects().includes(`${W}/free\tgcp`), projects());
    assert.strictEqual(statusItem.text, '$(account) ccprof: gcp · acme-bill');
  });

  await test('switching profile asks for confirmation and warns about conversations', async () => {
    state.warnings = [];
    state.warnAnswer = 'Continue';
    state.picks = ['personal', 'free'];
    await commands['ccprof.bind']();
    assert(state.warnings.some(w => w.includes('conversations')));
    assert(projects().includes(`${W}/free\tpersonal`));
    assert.strictEqual(statusItem.backgroundColor.id, 'statusBarItem.warningBackground');
  });

  await test('cancelling the confirmation changes nothing', async () => {
    state.warnAnswer = null;
    state.picks = ['work', 'free'];
    await commands['ccprof.bind']();
    assert(projects().includes(`${W}/free\tpersonal`));
  });

  await test('multi-root with different profiles → warning', async () => {
    state.folders = [folder('Work Repos/api'), folder('Personal/side-project')];
    await commands['ccprof.refresh']();
    assert(statusItem.text.endsWith('$(warning)'));
    assert(statusItem.tooltip.value.includes('first'));
  });

  await test('terminal with a different profile uses CCPROF_OVERRIDE', async () => {
    state.folders = [folder('free')];
    state.picks = ['gcp'];
    await commands['ccprof.openTerminal']();
    const t = state.terminals.pop();
    assert.deepStrictEqual(t.opts.env, { CCPROF_OVERRIDE: 'gcp' });
    assert.deepStrictEqual(t.sent, ['claude']);
  });

  await test('removing an inherited binding asks for confirmation', async () => {
    state.folders = [folder('Work Repos/ui')];
    state.warnings = [];
    state.warnAnswer = 'Remove Anyway';
    await commands['ccprof.unbind']();
    assert(state.warnings.some(w => w.includes('inherited')));
    assert(!projects().includes('Work Repos\twork'));
  });

  await test('missing ccprof → readable error', async () => {
    state.config['ccprof.path'] = '/does/not/exist/ccprof';
    state.errors = [];
    await commands['ccprof.bind']();
    assert(state.errors.some(e => e.includes('ccprof not found')), state.errors.join());
    delete state.config['ccprof.path'];
  });

  console.log(`\nResult: ${pass} passed, ${fail} failed`);
  fs.rmSync(T, { recursive: true, force: true });
  process.exit(fail ? 1 : 0);
})();
