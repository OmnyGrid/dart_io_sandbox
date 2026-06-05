## 1.0.1

- Docs: expanded the README with a dedicated **"Add command analysis
  (`CommandGuard`)"** usage section showing how to attach a `command_shield`-backed
  guard via `Sandbox.run(commandGuard: ...)`, configure `denyOnReview` /
  `neverConfirmCritical`, and use the `filter` / `confirm` hooks. Fixed the stale
  install snippet (`^0.1.0` → `^1.0.1`).
- Tests: substantially improved coverage (overall lib line coverage ~85%). Added
  unit tests for `SandboxAccessEvent`/`SandboxAccessType`, the `SandboxError`
  hierarchy and its factories, `SandboxConfig` defaults, sandboxed `Link`
  operations (create/update/target/rename plus escape rejection), and broader
  `File`/`Directory` surface (copy, length, stat, timestamps, `readAsLines`,
  append via `openWrite`, `createTemp`, async `list`, `parent` clamping). Extended
  the `package:file` adapter tests to cover `fromConfig`, `directory`/`link`,
  `stat`/`type`/`identical` and the directory accessors.
- No runtime/API changes.

## 1.0.0

- Optional `CommandGuard`: semantic, execution-free command analysis for
  `Sandbox.process`, backed by `package:command_shield`. Attach it via
  `Sandbox.run(commandGuard: ...)` or `SandboxConfig.commandGuard` to deny
  dangerous invocations of allowlisted executables. Off by default; a
  `command_shield` `review` verdict is treated as a denial (`denyOnReview`,
  fail-closed). Added `example/command_shield_example.dart`.
- `CommandGuard` pluggable hooks (sync or async `FutureOr`), both receiving a
  `CommandReview` with the full analysis:
  - `filter` — runs for every command and can override the verdict
    (force allow / review / deny, or `null` to keep `command_shield`'s).
  - `confirm` — runs when a command would be denied and can override the denial
    (e.g. an interactive "run anyway?"); overrides are flagged in the audit
    trail.
  `Sandbox.process.runSync` throws `UnsupportedError` if a hook returns a
  `Future` (use the async `run`/`start`).
  - `neverConfirmCritical` (default `true`): commands `command_shield`
    classifies as critical-severity denials (e.g. `rm -rf /`) can never be
    overridden by `confirm` — the callback is not consulted for them. Set to
    `false` to allow confirming even critical denials.

## 0.1.0

- Initial release.
- Zone-based filesystem sandbox via `IOOverrides`: sandboxed `File`, `Directory`,
  and `Link` confined to a configured root (full sync + async surface).
- Path resolution layer with `..`/absolute-path traversal blocking and
  access-time symlink-escape protection.
- `SandboxPolicy`: read-only mode, allow/deny path lists (deny overrides allow),
  and an executable allowlist. Pure, deterministic evaluation.
- `Sandbox.process`: opt-in, allowlisted, shell-free process execution.
- Network gate: `Socket` / `ServerSocket` creation (and, transitively,
  `HttpClient`) blocked unless `allowNetwork` is set. Raw sockets and UDP
  (`RawSocket`, `RawServerSocket`, `RawDatagramSocket`) have no `IOOverrides`
  hook and are a documented, non-interceptable gap.
- `onAccess` hook emitting `SandboxAccessEvent`s for every allowed/denied access.
- Nested sandboxes with policy intersection (never more permissive than parent).
- Optional `package:file` integration via `SandboxFileSystem`.
- Error hierarchy: `SandboxViolationError`, `SandboxPathError`,
  `SandboxPolicyError`, `SandboxProcessDeniedError`.
