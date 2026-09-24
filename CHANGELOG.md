# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
uses [semantic versioning](https://semver.org/).

## [0.4.0]

### Changed
- The command is now called **`ccprof`** (it was `ccm`), to avoid clashing with other tools.
  Environment variables are now `CCPROF_*`; the old `CCM_*` names still work.
- The VS Code extension is now `ccprof-vscode`, with `ccprof.*` commands and settings.

### Added
- Automatic migration from ccm: the installer moves `~/.config/ccm` to `~/.config/ccprof`,
  updates profile files and statuslines, replaces the old shell block and keeps
  `~/.local/share/ccm` as a link so VS Code keeps working.
- `ccm` remains available as an alias, with a notice, for a few versions.

## [0.3.0]

### Changed
- Everything is now in English: CLI messages, installer, VS Code extension and documentation.
- Help and README make it clear that you can create any number of profiles with any name
  (for example two personal accounts); `--type` only sets how a profile authenticates and is shown.

### Added
- `ccm current [dir]`: prints just the profile name, for shell prompts and scripts.
- `ccm rename <old> <new>`: renames a profile and updates its bindings, keeping logins and conversations.
- README banner and a "Why ccm" section.

## [0.2.0] — first public release

### Added
- `ccm` CLI: Team, personal and Vertex AI profiles, each with an isolated config dir.
- Project → profile bindings with longest-prefix matching (parent folders included).
- Fail-closed `claude` shim that clears account/provider/billing variables before every start.
- Wrapper mode for `claudeCode.claudeProcessWrapper`: the VS Code panel uses the profile too.
- `ccm which --json` and `ccm list --json`.
- Claude Code statusline showing the active profile.
- VS Code extension: status bar, binding from the Command Palette, terminal with profile,
  doctor, panel configuration.
- `curl | bash` installer with `--with-vscode` and `--uninstall`.
