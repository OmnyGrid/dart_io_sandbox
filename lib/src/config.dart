/// Configuration value object bundling everything needed to start a sandbox.
library;

import 'events.dart';
import 'policy.dart';
import 'process/command_guard.dart';
import 'process/command_rewriter.dart';

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

  /// Trusted command rewriters applied to every [Sandbox.process] command after
  /// it passes the allowlist and [commandGuard].
  final List<CommandRewriter> commandRewriters;

  /// Whether an intercepted `dart test` command is rewritten to an equivalent
  /// `dart_io_sandbox test` invocation. Defaults to `true`.
  final bool rewriteDartTest;

  /// Overrides the invocation prefix used by the `dart test` rewrite; see
  /// [Sandbox.run].
  final List<String>? dartTestRewritePrefix;

  const SandboxConfig({
    required this.root,
    this.policy = SandboxPolicy.readWrite,
    this.onAccess,
    this.commandGuard,
    this.commandRewriters = const [],
    this.rewriteDartTest = true,
    this.dartTestRewritePrefix,
  });
}
