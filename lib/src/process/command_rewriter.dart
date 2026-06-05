/// A general command-rewrite mechanism for [Sandbox.process].
///
/// A [CommandRewriter] is a host-configured, trusted transform that may replace
/// the executable and/or arguments of a command *after* it has already passed
/// the sandbox's allowlist and [CommandGuard] checks. The rewritten command is
/// spawned as-is (it is not re-checked), so rewriters are intended for
/// transparent substitutions controlled by the application embedding the
/// sandbox — for example, rewiring `dart test` to the `dart_io_sandbox test` CLI
/// so the nested test process is itself confined (see `dart_test_rewrite.dart`).
library;

/// The replacement produced by a [CommandRewriter]: a new [executable] and
/// [arguments] to run in place of the original command.
class CommandRewrite {
  /// The executable to run instead of the original.
  final String executable;

  /// The arguments to pass to [executable].
  final List<String> arguments;

  const CommandRewrite(this.executable, this.arguments);
}

/// Inspects a command and optionally returns a [CommandRewrite] to run in its
/// place, or `null` to leave the command unchanged.
typedef CommandRewriter =
    CommandRewrite? Function(String executable, List<String> arguments);

/// Applies [rewriters] in order, threading each one's result into the next, and
/// returns the final `(executable, arguments)`. A rewriter returning `null`
/// leaves the current command unchanged.
(String, List<String>) applyRewriters(
  List<CommandRewriter> rewriters,
  String executable,
  List<String> arguments,
) {
  var exe = executable;
  var args = arguments;
  for (final rewriter in rewriters) {
    final out = rewriter(exe, args);
    if (out != null) {
      exe = out.executable;
      args = out.arguments;
    }
  }
  return (exe, args);
}
