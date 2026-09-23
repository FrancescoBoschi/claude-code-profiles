# ccm for VS Code

A VS Code UI for [claude-code-profiles](https://github.com/FrancescoBoschi/claude-code-profiles)
(`ccm`). All the logic stays in the `ccm` CLI: the extension reads and writes the same
bindings you use from the terminal. Unofficial, not affiliated with Anthropic.

- **Status bar**: the workspace profile (for Vertex, the GCP project too). Red when the
  workspace is not bound, yellow for personal profiles (turn it off with
  `ccm.highlightPersonal`). In multi-root workspaces the tooltip shows every folder. Click it for the menu.
- **ccm: Bind Profile to Workspace**: pick the profile, then whether it applies to this
  project only or to its whole parent folder. Warns you when a project that already has
  conversations moves to another profile.
- **ccm: Remove Binding**, **Open Claude Terminal with Profile…**, **Show Profiles and
  Projects**, **Doctor**.
- **ccm: Configure Claude Code Panel**: sets `claudeCode.claudeProcessWrapper` to the ccm
  shim, so the official panel uses the workspace profile too. The extension checks this
  setting on startup and offers to fix it.

Requires ccm 0.3.0 or later. Install: `code --install-extension ccm-vscode.vsix`
