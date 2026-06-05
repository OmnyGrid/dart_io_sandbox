# dart_io_sandbox

[![pub package](https://img.shields.io/pub/v/dart_io_sandbox.svg?logo=dart&logoColor=00b9fc)](https://pub.dev/packages/dart_io_sandbox)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Dart CI](https://github.com/OmnyGrid/dart_io_sandbox/actions/workflows/dart.yml/badge.svg?branch=master)](https://github.com/OmnyGrid/dart_io_sandbox/actions/workflows/dart.yml)
[![GitHub Tag](https://img.shields.io/github/v/tag/OmnyGrid/dart_io_sandbox?logo=git&logoColor=white)](https://github.com/OmnyGrid/dart_io_sandbox/releases)
[![New Commits](https://img.shields.io/github/commits-since/OmnyGrid/dart_io_sandbox/latest?logo=git&logoColor=white)](https://github.com/OmnyGrid/dart_io_sandbox/network)
[![Last Commits](https://img.shields.io/github/last-commit/OmnyGrid/dart_io_sandbox?logo=git&logoColor=white)](https://github.com/OmnyGrid/dart_io_sandbox/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/OmnyGrid/dart_io_sandbox?logo=github&logoColor=white)](https://github.com/OmnyGrid/dart_io_sandbox/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/OmnyGrid/dart_io_sandbox?logo=github&logoColor=white)](https://github.com/OmnyGrid/dart_io_sandbox)
[![License](https://img.shields.io/github/license/OmnyGrid/dart_io_sandbox?logo=open-source-initiative&logoColor=green)](https://github.com/OmnyGrid/dart_io_sandbox/blob/master/LICENSE)

A **Zone-based filesystem and process sandbox** for Dart, written in **pure
Dart** on top of `dart:io`'s `IOOverrides`. Run code with `Sandbox.run` and all
standard `dart:io` filesystem access is **transparently confined** to a root
directory: path-traversal and symlink escapes are blocked, a declarative
policy governs reads / writes / deletes, process execution is gated behind an
allowlist, network access is blocked by default, and **every access is
observable** through a hook.

It plugs into ordinary code — no special filesystem API to adopt. The same
`File('data.txt')` your code already writes becomes sandboxed inside the zone.
Optional `package:file` integration is included.

> ## ⚠️ This is NOT an OS-level sandbox
>
> `dart_io_sandbox` is **in-process, cooperative confinement**. It works by
> overriding the `dart:io` entity constructors inside a Dart `Zone`. It is a
> strong guardrail for **semi-trusted code that uses the normal `dart:io`
> APIs** — not a security boundary against hostile code. It does **not** stop
> native code, `dart:ffi`, direct syscalls, `Process.run` issued directly via
> `dart:io` (use `Sandbox.process`), raw sockets / UDP (`RawSocket`,
> `RawServerSocket`, `RawDatagramSocket` — `IOOverrides` has no hook for them),
> or isolates that install their own overrides. For untrusted/adversarial code,
> layer it **on top of** a real OS sandbox (containers, seccomp, jails, VMs).

## API Documentation

See the [API Documentation][api_doc] for a full list of classes and members.

[api_doc]: https://pub.dev/documentation/dart_io_sandbox/latest/
[command_shield]: https://pub.dev/packages/command_shield

## Features

- **Filesystem jail.** Every `File`, `Directory`, and `Link` is confined to the
  configured root. Relative paths resolve against the root; any escape throws a
  `SandboxViolationError`. Full sync **and** async surface, so synchronous calls
  cannot be used to bypass the jail.
- **Traversal & symlink protection.** `../` traversal and absolute-path escapes
  are rejected lexically; symlinks are re-canonicalized and re-checked at access
  time, so a link whose target points outside the root cannot be read, and
  escaping links cannot be created.
- **Deterministic policy layer.** `SandboxPolicy` supports read-only mode, allow
  lists and deny lists (deny always wins). Evaluation is a pure, side-effect-free
  function — trivially unit-testable.
- **Process allowlist.** Opt-in process execution restricted to named
  executables, **never run through a shell**, with shell-metacharacter rejection.
- **Optional command analysis.** Attach a `CommandGuard` (backed by
  [`package:command_shield`][command_shield]) to add semantic, execution-free
  analysis on top of the allowlist — an allowlisted `bash`/`git`/`rm` invoked
  destructively can still be denied. Off by default; fail-closed on `review`.
  Pluggable `filter` (override the verdict for every command) and `confirm`
  (approve a would-be denial) hooks, sync or async.
- **Network gate.** `Socket` / `ServerSocket` creation — and, transitively,
  `HttpClient` — is blocked unless `allowNetwork: true`. Raw sockets and UDP are
  **not** interceptable (see Limitations).
- **Observability.** An `onAccess` hook receives a `SandboxAccessEvent` for every
  allowed and denied operation — a complete audit trail.
- **Composable nesting.** Sandboxes nest; a nested sandbox must live inside its
  parent and can never be more permissive than it (policies are intersected).
- **`package:file` integration.** Expose a sandbox as a `package:file`
  `FileSystem` via `SandboxFileSystem`.
- **Tested.** Unit + integration tests cover path handling, policy, file
  operations, the process layer, the command guard, symlink escapes, nesting and
  the adapter.

## Architecture

```
            Your code (plain dart:io)
                       │
        File / Directory / Link / Socket(...)
                       │
                       ▼
          IOOverrides (Dart Zone)  ◄── Sandbox.run installs SandboxIOOverrides
                       │
      ┌────────────────┼─────────────────┐
      ▼                ▼                  ▼
  Path resolver     Policy           Network gate
  (traversal +     (read-only,       (allowNetwork)
   symlink jail)    allow/deny)
      │                │
      └────────┬───────┘
               ▼
  Sandboxed File / Directory / Link  ──►  native dart:io (confined real path)
               │
               ▼
        onAccess hook  (audit: allow + deny events)

  Sandbox.process ──► allowlist + no-shell guard ──► Process.run / start
```

`IOOverrides` only intercepts the **construction** of `File`/`Directory`/`Link`,
so each one is returned as a policy-enforcing wrapper that delegates to a native
entity bound to an already-resolved, contained real path.

```
lib/
├── dart_io_sandbox.dart      # public library (exports)
└── src/
    ├── sandbox.dart          # Sandbox.run + the IOOverrides interception layer
    ├── context.dart          # per-sandbox, zone-scoped state
    ├── config.dart           # SandboxConfig value object
    ├── policy.dart           # SandboxPolicy + deterministic evaluation
    ├── events.dart           # SandboxAccessEvent + onAccess hook
    ├── errors.dart           # SandboxError hierarchy
    ├── file_adapter.dart     # package:file integration (SandboxFileSystem)
    ├── path/                 # resolver.dart (resolution) + validator.dart (containment)
    ├── fs/                   # sandboxed File / Directory / Link + shared mixin
    └── process/              # allowlisted, shell-free process execution
```

## Getting started

```yaml
dependencies:
  dart_io_sandbox: ^0.1.0
```

## Usage

### Run code in a sandbox

```dart
import 'dart:io';
import 'package:dart_io_sandbox/dart_io_sandbox.dart';

await Sandbox.run(
  root: '/tmp/sandbox',
  policy: SandboxPolicy(
    readOnly: false,
    allowProcess: true,
    allowedPaths: ['/tmp/sandbox/data'],
    deniedPaths: ['/tmp/sandbox/data/secret'],
    allowedExecutables: ['echo'],
  ),
  onAccess: (event) => print(event), // [ALLOW] write /tmp/sandbox/data/x ...
  action: () async {
    // Plain dart:io — automatically sandboxed.
    final file = File('data/notes.txt');
    await Directory('data').create(recursive: true);
    await file.writeAsString('hello');
    print(await file.readAsString());

    // Allowlisted process execution (never via a shell).
    final result = await Sandbox.process.run('echo', ['sandboxed']);
    print(result.stdout);

    // The following all throw:
    //   File('../../etc/passwd');             // SandboxViolationError (traversal)
    //   File('/etc/passwd');                  // SandboxViolationError (absolute)
    //   File('data/secret/k').writeAsString;  // SandboxPolicyError (deny list)
    //   Sandbox.process.run('rm', ['-rf']);   // SandboxProcessDeniedError
    //   Socket.connect('host', 80);           // SandboxViolationError (network)
  },
);
```

A complete runnable example lives at [`example/main.dart`][example_file].

[example_file]: example/main.dart

### Enforce a policy

```dart
const policy = SandboxPolicy(
  readOnly: true,                       // blocks all writes/deletes/renames
  allowedPaths: ['/srv/data'],          // empty => everything within the root
  deniedPaths: ['/srv/data/secrets'],   // deny always overrides allow
  allowProcess: false,                  // no process execution
  allowNetwork: false,                  // no sockets (default)
  allowedExecutables: ['git', 'echo'],  // allowlist (fail-closed when empty)
);
```

Policy evaluation is a pure function, so it is testable without any sandbox:

```dart
policy.denyReason(AccessMode.write, '/srv/data/x');        // 'policy is read-only; ...'
policy.denyReason(AccessMode.read,  '/srv/data/secrets/k'); // 'covered by deny list ...'
policy.denyReason(AccessMode.read,  '/srv/data/x');         // null  => allowed
```

### Use the `package:file` adapter

```dart
import 'package:file/file.dart';
import 'package:dart_io_sandbox/dart_io_sandbox.dart';

// Self-contained: confined wherever it is used.
final FileSystem fs = SandboxFileSystem.bound(root: '/tmp/sandbox');
await fs.file('a.txt').writeAsString('hi'); // confined under the root
fs.file('../../etc/passwd');                // throws SandboxViolationError
```

Inside a `Sandbox.run` body the default `SandboxFileSystem()` (and even a plain
`LocalFileSystem`) is automatically sandboxed, because `package:file` builds its
`dart:io` delegate at entity-construction time within the zone.

## How it works

### Path resolution (a jail, not a chroot)

The current working directory inside the sandbox starts at the canonical root.
A path is resolved by joining relative inputs onto the cwd, normalizing `.`/`..`
**lexically**, and then asserting the result is contained within the root.
Anything that escapes — `../../etc/passwd`, `/etc/passwd` — throws rather than
being silently clamped.

### Symlink containment

Lexical checks alone are not enough: a symlink whose name is inside the root can
point outside it. Before each access, the longest existing prefix of the target
path is canonicalized (symlinks resolved) and re-checked for containment, so
links created **after** the sandbox starts are still caught. Creating a link
whose target would escape is rejected outright.

### Policy & nesting

`deniedPaths` always override `allowedPaths`; read-only mode blocks every write,
delete and rename. When a sandbox is created inside another, its root must live
within the parent's root and its policy is **intersected** with the parent's —
read-only is OR-ed, process/network are AND-ed, deny lists are unioned and the
executable allowlist is intersected — so a nested sandbox can never widen the
permissions it was granted.

### Process execution

There is no `IOOverrides` hook for processes, so `Sandbox.process` is a separate,
explicit API. It requires `allowProcess`, an executable on the allowlist, runs
**without a shell**, and rejects arguments containing shell metacharacters.

### Optional command analysis (`CommandGuard`)

The executable allowlist answers *"is this executable allowed?"* but not *"is
this specific command dangerous?"*. Attach a `CommandGuard` — backed by
[`package:command_shield`][command_shield] — to analyse each invocation and
deny dangerous ones (e.g. an allowlisted `bash`/`rm` used destructively):

```dart
import 'package:command_shield/command_shield.dart' show CommandSyntax;
import 'package:dart_io_sandbox/dart_io_sandbox.dart';

await Sandbox.run(
  root: root,
  policy: const SandboxPolicy(
    allowProcess: true,
    allowedExecutables: ['bash', 'echo'],
  ),
  commandGuard: CommandGuard.forSyntax(CommandSyntax.bash),
  action: () async {
    await Sandbox.process.run('echo', ['hi']);          // allowed
    await Sandbox.process.run('bash', ['-c', 'rm -rf /']); // SandboxProcessDeniedError
  },
);
```

The feature is **off** unless a guard is attached, so existing behaviour is
unchanged. The guard runs *after* the shell-metacharacter check, so it sees a
metacharacter-free, unambiguously reconstructed command string. A
`command_shield` `review` verdict is treated as a denial by default
(`denyOnReview: true`, fail-closed); pass `denyOnReview: false` to permit (but
still audit) reviewed commands. For full control build the guard from a
`CommandShield` directly: `CommandGuard(CommandShield(policy: ...))`.

#### Custom hooks: `filter` and `confirm`

Two optional callbacks plug into the guard, both receiving a `CommandReview`
(the executable, arguments, reconstructed `command`, and the full
`command_shield` analysis `result`). They may be **synchronous or asynchronous**
(`FutureOr`):

- **`filter`** runs for *every* command and can override the verdict — return a
  `CommandDecision` (force `allow` / `review` / `deny`) or `null` to keep
  `command_shield`'s verdict. Use it for project-specific policy on top of the
  analysis.
- **`confirm`** runs whenever a command would be *denied* and decides whether to
  override the denial (return `true` to run it anyway) — e.g. an interactive
  "run anyway?" prompt. A confirmed override is still recorded in the audit
  trail.

By default (`neverConfirmCritical: true`) the most dangerous commands — those
`command_shield` classifies as **critical-severity denials** (e.g. `rm -rf /`) —
can **never** be confirmed: `confirm` is not even consulted for them. Pass
`neverConfirmCritical: false` to let `confirm` override even those.

```dart
final guard = CommandGuard.forSyntax(
  CommandSyntax.bash,
  filter: (review) =>
      review.command.contains('/etc') ? CommandDecision.deny : null,
  confirm: (review) async => await promptYesNo('Run "${review.command}"?'),
);
```

> **`runSync` caveat:** `Sandbox.process.runSync` cannot await. If `filter` or
> `confirm` returns a `Future`, `runSync` throws an `UnsupportedError` — use the
> async `run`/`start` instead.

> Command analysis is **not** composed across nested sandboxes — the innermost
> non-null guard wins (the same inheritance model used for `onAccess`).

### Network gate (what it can and cannot intercept)

`IOOverrides` exposes hooks for `Socket.connect`, `Socket.startConnect` and
`ServerSocket.bind`, so those — and `HttpClient`, which connects through
`Socket.connect` internally — are gated by `allowNetwork`. There is **no**
`IOOverrides` hook for `RawSocket`, `RawServerSocket` or `RawDatagramSocket`
(UDP), so those cannot be intercepted in-process and are **not** blocked. If you
must deny UDP/raw sockets, do it at the OS layer (see the warning above).

## Errors

All errors extend `SandboxError` and carry the attempted path/action and a reason:

| Error | Raised when |
| --- | --- |
| `SandboxViolationError` | Escape attempt: traversal, absolute path, symlink, or blocked network. |
| `SandboxPathError` | Malformed or unresolvable path (empty, null byte, ...). |
| `SandboxPolicyError` | Denied by read-only / allow / deny rules. |
| `SandboxProcessDeniedError` | Process disabled, not allowlisted, or contains a blocked pattern. |

## Limitations

- **Cooperative only** — see the warning above. Not robust against hostile code.
- Direct `Process.run` from `dart:io` is **not** intercepted (no override hook
  exists); use `Sandbox.process`.
- The network gate covers `Socket` / `ServerSocket` / `HttpClient` only.
  `RawSocket`, `RawServerSocket` and `RawDatagramSocket` (UDP) have **no**
  `IOOverrides` hook and therefore **bypass** `allowNetwork`.
- `getSystemTempDirectory()` is redirected to a `.tmp` directory inside the root.
- Absolute paths must be expressed against the **canonical** root (symlinks
  resolved); e.g. on macOS `/tmp/...` is canonicalized to `/private/tmp/...`.
- Confinement is per-zone; code that escapes the zone (new isolates, FFI) is not
  covered.

## Running the example and tests

```sh
dart run example/main.dart                    # runnable demo of the full feature set
dart run example/command_shield_example.dart  # optional CommandGuard demo
dart test                                     # full unit + integration suite
```

## Source

The official source code is [hosted @ GitHub][github_repo]:

- https://github.com/OmnyGrid/dart_io_sandbox

[github_repo]: https://github.com/OmnyGrid/dart_io_sandbox

# Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

# Contribution

Any help from the open-source community is always welcome and needed:

- Found an issue?
    - Please fill a bug report with details.
- Wish a feature?
    - Open a feature request with use cases.
- Are you using and liking the project?
    - Promote the project: create an article, do a post or make a donation.
- Are you a developer?
    - Fix a bug and send a pull request.
    - Implement a new feature.
    - Improve the Unit Tests.
- Have you already helped in any way?
    - **Many thanks from me, the contributors and everybody that uses this project!**

*If you donate 1 hour of your time, you can contribute a lot,
because others will do the same, just be part and start with your 1 hour.*

[tracker]: https://github.com/OmnyGrid/dart_io_sandbox/issues

# Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

[Apache License - Version 2.0][apache_license]

[apache_license]: https://www.apache.org/licenses/LICENSE-2.0.txt
