/// Configuration value object bundling everything needed to start a sandbox.
library;

import 'events.dart';
import 'policy.dart';
import 'process/command_guard.dart';

/// Immutable description of a sandbox: its [root], its [policy], and an optional
/// [onAccess] hook.
///
/// This is a convenience aggregate; [Sandbox.run] accepts the same fields
/// directly. Use [SandboxConfig] when you want to pass a reusable configuration
/// around your application.
class SandboxConfig {
  /// The directory that bounds the sandbox. Created if it does not exist. All
  /// resolved real paths must live within its canonical form.
  final String root;

  /// The access policy. Defaults to read-write within the root, no process, no
  /// network.
  final SandboxPolicy policy;

  /// Optional observer invoked for every allowed and denied access.
  final SandboxAccessHook? onAccess;

  /// Optional semantic command-analysis gate for [Sandbox.process], backed by
  /// `package:command_shield`. When `null` (the default), process execution is
  /// governed by the executable allowlist alone.
  final CommandGuard? commandGuard;

  const SandboxConfig({
    required this.root,
    this.policy = SandboxPolicy.readWrite,
    this.onAccess,
    this.commandGuard,
  });
}
