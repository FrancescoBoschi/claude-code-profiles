# Security policy

ccprof decides which Claude Code account, cloud project and API key a session uses, so a bug
here can mean running with the wrong account or billing the wrong project. Reports are very welcome.

## Reporting a vulnerability

Please **do not open a public issue**. Use GitHub's private reporting instead:
**Security → Report a vulnerability** on this repository. I aim to reply within a few days.

Please include the ccprof version (`ccprof version`), your OS and shell, and the steps to
reproduce. Never paste real tokens, API keys or credentials: redact them.

## In scope

- A profile's environment leaking into another project, or variables that should be cleared
  (account, provider, billing, cloud credentials) reaching Claude Code.
- `claude` starting in an unbound folder instead of refusing (fail-closed bypass).
- API keys being written anywhere other than the OS keychain, or exposed to other users.
- The installer or the shim running code from an unexpected location.

## Supported versions

Only the latest release receives fixes. Update with the installer or `./install.sh`.

## What ccprof does not do

ccprof does not copy or transmit your Claude Code, gcloud or aws logins (`ccprof doctor` only
checks that they exist), and it makes no network calls at runtime. Only the installer downloads files, from this repository's releases.
