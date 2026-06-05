/// Converts a sandbox configuration into `dart_io_sandbox` CLI arguments, and
/// the built-in rewriter that rewires an intercepted `dart test` command to the
/// `dart_io_sandbox test` CLI so the nested test process is itself confined.
library;

import 'package:path/path.dart' as p;

import '../context.dart';
import '../policy.dart';
import 'command_guard.dart';
import 'command_rewriter.dart';

/// Returns the `dart_io_sandbox` sandbox flags that reproduce [root] + [policy]
/// (and, when given, [commandGuard]).
///
/// The result is the flag list for the `test`/`config` commands — it does not
/// include the command name or any test-runner arguments. It starts from the
/// clean `none` preset so the list flags (`--allow-exe`/`--allow-path`/
/// `--deny-path`) *reproduce* the policy rather than appending to a preset's
/// defaults.
///
/// Only the guard's serialisable settings are carried: its `defaultSyntax`,
/// `denyOnReview` and `neverConfirmCritical`. A custom `command_shield` policy
/// and any `filter`/`confirm` closures cannot cross a process boundary and are
/// not reproduced.
List<String> sandboxCliArgs(
  String root,
  SandboxPolicy policy, {
  CommandGuard? commandGuard,
}) {
  return [
    '--preset',
    'none',
    '--root',
    root,
    policy.readOnly ? '--read-only' : '--no-read-only',
    policy.allowNetwork ? '--allow-network' : '--no-allow-network',
    policy.allowProcess ? '--allow-process' : '--no-allow-process',
    for (final exe in policy.allowedExecutables) ...['--allow-exe', exe],
    for (final path in policy.allowedPaths) ...['--allow-path', path],
    for (final path in policy.deniedPaths) ...['--deny-path', path],
    if (commandGuard != null) ...[
      '--command-guard',
      '--command-guard-syntax',
      commandGuard.shield.defaultSyntax.name,
      if (commandGuard.denyOnReview)
        '--command-guard-deny-on-review'
      else
        '--no-command-guard-deny-on-review',
      if (commandGuard.neverConfirmCritical)
        '--command-guard-never-confirm-critical'
      else
        '--no-command-guard-never-confirm-critical',
    ] else
      '--no-command-guard',
  ];
}

/// A [CommandRewriter] that rewrites `dart test ...` (run through
/// [Sandbox.process]) into an equivalent `dart_io_sandbox test ...` invocation
/// whose sandbox flags reproduce [ctx]'s current policy and command guard.
///
/// Returns `null` for anything that is not `dart test` (matched by executable
/// basename `dart`/`dart.exe` with `test` as the first argument), so it is a
/// no-op for every other command.
///
/// The replacement command is, by default,
/// `<original dart> run dart_io_sandbox test <flags> <original test args>`. Set
/// [SandboxContext.dartTestRewritePrefix] to override the invocation prefix
/// (e.g. `['dart_io_sandbox']` for a globally-activated binary). The rewrite is
/// idempotent: the result's first argument is `run` (or the global executable),
/// so it never re-matches `dart test`.
CommandRewrite? rewriteDartTestCommand(
  SandboxContext ctx,
  String executable,
  List<String> arguments,
) {
  if (p.basenameWithoutExtension(executable) != 'dart') return null;
  if (arguments.isEmpty || arguments.first != 'test') return null;

  final flags = sandboxCliArgs(
    ctx.realRoot,
    ctx.policy,
    commandGuard: ctx.commandGuard,
  );
  final prefix =
      ctx.dartTestRewritePrefix ?? [executable, 'run', 'dart_io_sandbox'];

  return CommandRewrite(prefix.first, [
    ...prefix.skip(1),
    'test',
    ...flags,
    ...arguments.skip(1),
  ]);
}
