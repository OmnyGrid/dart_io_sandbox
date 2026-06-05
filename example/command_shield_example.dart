// Demonstrates the optional command-analysis layer backed by
// `package:command_shield`.
//
// The executable allowlist answers "is this executable allowed?". A CommandGuard
// adds the missing question — "is this *command* dangerous?" — so an allowlisted
// `bash` invoked destructively can still be denied. The feature is off unless a
// CommandGuard is attached to the sandbox.
//
// Two optional callbacks extend the analysis:
//   * `filter`  — runs for every command, with the analysis already computed,
//                 and can override the verdict (allow / review / deny).
//   * `confirm` — runs when a command would be denied, for a last-chance
//                 "run anyway?" decision (here: an auto-decline that audits).
import 'dart:io';

import 'package:command_shield/command_shield.dart'
    show CommandDecision, CommandSyntax;
import 'package:dart_io_sandbox/dart_io_sandbox.dart';

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('sandbox_shield').path;

  final guard = CommandGuard.forSyntax(
    CommandSyntax.bash,
    // A per-command filter: block any command that touches `/etc`, even if
    // command_shield would otherwise allow it. Return `null` to keep the
    // analysis verdict.
    filter: (review) {
      if (review.command.contains('/etc')) return CommandDecision.deny;
      return null;
    },
    // A confirmation hook consulted before a denial becomes final. A real app
    // might prompt the user (e.g. stdin.readLineSync()); here we simply log and
    // decline, so nothing dangerous runs. Note it is NOT consulted for
    // critical-severity denials (see neverConfirmCritical below).
    confirm: (review) {
      print('confirm? denied command "${review.command}" — declining');
      return false;
    },
    // Default: critical-severity denials (e.g. `rm -rf /`) can never be
    // confirmed — the confirm hook is bypassed for them entirely.
    neverConfirmCritical: true,
  );

  await Sandbox.run(
    root: root,
    policy: const SandboxPolicy(
      allowProcess: true,
      // `bash`/`cat`/`rm` are allowlisted; the guard is what stops dangerous use.
      allowedExecutables: ['bash', 'cat', 'echo', 'rm'],
    ),
    commandGuard: guard,
    onAccess: (event) => print('audit: $event'),
    action: () async {
      // Benign command: allowed by the guard and executed.
      final ok = await Sandbox.process.run('echo', ['hello from the sandbox']);
      print('echo => exit=${ok.exitCode} stdout=${ok.stdout.trim()}');

      // Blocked by the custom filter (touches /etc), before anything runs.
      try {
        await Sandbox.process.run('cat', ['/etc/hosts']);
      } on SandboxProcessDeniedError catch (e) {
        print('blocked by filter: ${e.reason}');
      }

      // Review-level denial: command_shield holds `bash -c` for review (treated
      // as a denial), so the confirm hook gets the last word — and declines.
      try {
        await Sandbox.process.run('bash', ['-c', 'echo hi']);
      } on SandboxProcessDeniedError catch (e) {
        print('blocked (review): ${e.reason}');
      }

      // Critical denial: `rm -rf /` is classified critical, so the confirm hook
      // is NOT consulted at all — it can never be overridden.
      try {
        await Sandbox.process.run('rm', ['-rf', '/']);
      } on SandboxProcessDeniedError catch (e) {
        print('blocked (critical, no confirm): ${e.reason}');
      }
    },
  );

  Directory(root).deleteSync(recursive: true);
}
