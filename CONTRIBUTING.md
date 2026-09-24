# Contributing

Thanks! A few rules keep ccprof simple and reliable.

## Principles
- **The CLI is the single source of truth.** The VS Code extension holds no profile logic:
  it calls `ccprof ... --json`. New features start in the CLI.
- **Fail-closed.** When in doubt, `claude` does not start: a clear error beats the wrong account.
- **No dependencies** beyond bash, awk, sed and (for Vertex) gcloud.

## Shell compatibility
Scripts must run on the **bash 3.2 that ships with macOS**. So: no associative arrays,
`mapfile`, `readarray` or `${var,,}`. With `set -u`, use `${1+"$@"}` instead of `"$@"`.

## Tests
```bash
bash tests/smoke.sh          # CLI and shim (temporary HOME, fake claude)
node vscode/test/run.js      # extension, with a simulated vscode API and the real ccprof
shellcheck -s bash bin/ccprof bin/ccm shims/claude lib/ccprof-common.sh install.sh tests/smoke.sh
```
CI runs them on Linux and macOS on every push and pull request.

## Cutting a release
1. Update `CCPROF_VERSION` in `lib/ccprof-common.sh`, `version` in `vscode/package.json` and `CHANGELOG.md`.
2. `git tag vX.Y.Z && git push origin vX.Y.Z`: the GitHub Action publishes the release with
   `ccprof.tar.gz` and `ccprof-vscode.vsix`.
