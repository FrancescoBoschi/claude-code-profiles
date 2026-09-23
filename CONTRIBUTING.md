# Contributing

Thanks! A few rules keep ccm simple and reliable.

## Principles
- **The CLI is the single source of truth.** The VS Code extension holds no profile logic:
  it calls `ccm ... --json`. New features start in the CLI.
- **Fail-closed.** When in doubt, `claude` does not start: a clear error beats the wrong account.
- **No dependencies** beyond bash, awk, sed and (for Vertex) gcloud.

## Shell compatibility
Scripts must run on the **bash 3.2 that ships with macOS**. So: no associative arrays,
`mapfile`, `readarray` or `${var,,}`. With `set -u`, use `${1+"$@"}` instead of `"$@"`.

## Tests
```bash
bash tests/smoke.sh          # CLI and shim (temporary HOME, fake claude)
node vscode/test/run.js      # extension, with a simulated vscode API and the real ccm
shellcheck -s bash bin/ccm shims/claude lib/ccm-common.sh install.sh tests/smoke.sh
```
CI runs them on Linux and macOS on every push and pull request.

## Cutting a release
1. Update `CCM_VERSION` in `lib/ccm-common.sh`, `version` in `vscode/package.json` and `CHANGELOG.md`.
2. `git tag vX.Y.Z && git push origin vX.Y.Z`: the GitHub Action publishes the release with
   `ccm.tar.gz` and `ccm-vscode.vsix`.
