## 1.2.2

- Upgraded dependencies, most notably `command_shield` to `^1.1.0`.
- Bumped `path` (`^1.9.1`), `file` (`^7.0.1`), `args` (`^2.7.0`), `yaml`
  (`^3.1.3`), `async` (`^2.13.1`) and `stream_channel` (`^2.1.4`).
- Bumped dev dependencies `lints` (`^6.1.0`) and `test` (`^1.31.1`).

## 1.2.1

- Fix: `dart_io_sandbox test` could not resolve `package:test` (or the project's
  own libraries) when run against a project that does not itself depend on
  `dart_io_sandbox` — e.g. after `dart pub global activate`, the documented
  install path. Each suite isolate was spawned with the CLI's own package config
  (`Isolate.packageConfig`), which omits `test` (a dev-dependency, stripped from
  a standalone install) and the project's packages. `SandboxVMPlatform` now
  spawns each isolate with a **merged** package config: the project-under-test's
  resolution (its `test`, `test_core` and own libraries) plus the CLI-only
  packages the generated bootstrap imports (`dart_io_sandbox`, `command_shield`
  and their deps), the project winning on collisions. Falls back to the CLI
  config unchanged when the project has no `.dart_tool/package_config.json`.

## 1.2.0

- Network gate now covers **HTTPS**. A new `SandboxHttpOverrides` (installed by
  `Sandbox.run` alongside `SandboxIOOverrides`) wraps every `HttpClient` created
  inside the sandbox and checks each request against `allowNetwork`. Previously
  the gate relied on `IOOverrides`, which only sees `Socket.connect` — so
  `http://` was gated but `https://` (via `SecureSocket`) slipped through. Now
  both are blocked when `allowNetwork` is false. (Raw `RawSocket` /
  `RawDatagramSocket` / UDP still have no override hook and remain uninterceptable.)
- Command rewriting for `Sandbox.process`. `Sandbox.run` / `SandboxConfig` gain
  `commandRewriters` — a list of trusted `CommandRewriter` transforms applied to
  every process command *after* it passes the allowlist and `CommandGuard`
  (transparent substitutions, not re-checked). Exposes `CommandRewrite`,
  `CommandRewriter` and `applyRewriters`.
- Auto-rewires `dart test`. A built-in rewriter (`rewriteDartTest`, **default
  `true`**) turns an intercepted `dart test ...` into `dart run dart_io_sandbox
  test <flags> ...`, where `<flags>` reproduce the current sandbox's policy and
  the serialisable part of its `CommandGuard`, so the nested test process is
  itself confined. The invocation prefix is configurable via
  `dartTestRewritePrefix` (e.g. `['dart_io_sandbox']` for a global binary).
- New public helper `sandboxCliArgs(root, policy, {commandGuard})` converts a
  sandbox configuration to the equivalent `dart_io_sandbox` CLI flags.
- CLI: added a clean `none` base preset and `--command-guard` /
  `--command-guard-syntax` / `--command-guard-deny-on-review` /
  `--command-guard-never-confirm-critical` flags so a reproduced configuration
  parses back exactly (covered by a round-trip test).

## 1.1.0

- New `dart_io_sandbox` command-line tool. Its `test` command runs a Dart test
  suite like `dart test`, but every test isolate executes inside a `Sandbox.run`
  jail. It overrides the test runner's VM platform (via `registerPlatformPlugin`)
  so each spawned suite isolate installs the sandbox in its own bootstrap —
  preserving `dart test` parallelism (`-j`), filtering, reporters and exit codes
  while confining test bodies. Additional commands: `config` (print the resolved
  configuration), `presets` (list built-in presets) and `help`.
- Capabilities are configured by a `--preset` (`safe` / `paranoid`), an optional
  YAML file (`--config`), and CLI overrides (`--root`, `--read-only`,
  `--allow-network`, `--allow-process`, `--allow-exe`, `--allow-path`,
  `--deny-path`, `--audit`), layered preset < YAML < flags. The default `safe`
  preset is read-write in the root with network allowed, `dart`/`flutter`/`pub`
  on the process allowlist, and a bash `CommandGuard`. All other arguments to
  `test` are forwarded verbatim to the test runner. See `example/sandbox.yaml`.
- Adds `args`, `yaml`, `async`, `stream_channel`, `test_core` and `test_api` as
  dependencies (used by the CLI; library-only consumers get them transitively).

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
