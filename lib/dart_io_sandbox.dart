/// A Zone-based filesystem and process sandbox for Dart, built on
/// `dart:io`'s `IOOverrides`.
///
/// Run code with [Sandbox.run] to confine all `dart:io` filesystem access to a
/// root directory, block path-traversal and symlink escapes, enforce
/// read-only / allow / deny policies, gate process execution behind an
/// allowlist, and observe every access via a hook.
///
/// > **Not an OS sandbox.** This is in-process, cooperative confinement built on
/// > `IOOverrides`. It constrains code that uses the standard `dart:io` APIs. It
/// > does **not** stop native code, FFI, isolates spawned with their own zones,
/// > or direct syscalls, and it cannot intercept `Process.run` issued through
/// > `dart:io` directly (use [Sandbox.process]). Treat it as a guardrail for
/// > semi-trusted code, not a security boundary for hostile code.
library;

export 'src/config.dart';
export 'src/errors.dart';
export 'src/events.dart';
export 'src/file_adapter.dart' show SandboxFileSystem;
export 'src/policy.dart' show SandboxPolicy, AccessMode;
export 'src/process/sandbox_process.dart' show SandboxProcessManager;
export 'src/sandbox.dart' show Sandbox, SandboxIOOverrides;
