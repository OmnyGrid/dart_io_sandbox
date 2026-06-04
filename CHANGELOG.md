## 0.1.0

- Initial release.
- Zone-based filesystem sandbox via `IOOverrides`: sandboxed `File`, `Directory`,
  and `Link` confined to a configured root (full sync + async surface).
- Path resolution layer with `..`/absolute-path traversal blocking and
  access-time symlink-escape protection.
- `SandboxPolicy`: read-only mode, allow/deny path lists (deny overrides allow),
  and an executable allowlist. Pure, deterministic evaluation.
- `Sandbox.process`: opt-in, allowlisted, shell-free process execution.
- Network gate: socket creation blocked unless `allowNetwork` is set.
- `onAccess` hook emitting `SandboxAccessEvent`s for every allowed/denied access.
- Nested sandboxes with policy intersection (never more permissive than parent).
- Optional `package:file` integration via `SandboxFileSystem`.
- Error hierarchy: `SandboxViolationError`, `SandboxPathError`,
  `SandboxPolicyError`, `SandboxProcessDeniedError`.
