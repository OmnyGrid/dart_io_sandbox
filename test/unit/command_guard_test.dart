import 'dart:io';

import 'package:command_shield/command_shield.dart';
import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  group('CommandGuard.evaluateSync (analysis mapping)', () {
    final guard = CommandGuard.forSyntax(CommandSyntax.bash);

    test('allows a benign command', () {
      expect(guard.evaluateSync('echo', const ['hello']).allowed, isTrue);
      expect(guard.evaluateSync('git', const ['status']).allowed, isTrue);
    });

    test('denies a dangerous command with an explanation', () {
      final outcome = guard.evaluateSync('rm', const ['-rf', '/']);
      expect(outcome.allowed, isFalse);
      expect(outcome.reason, contains('command_shield'));
    });

    test('treats a review verdict as denial by default (fail-closed)', () {
      // `rm -rf /tmp/foo` is a REVIEW verdict in command_shield.
      final outcome = guard.evaluateSync('rm', const ['-rf', '/tmp/foo']);
      expect(outcome.allowed, isFalse);
      expect(outcome.reason, contains('review'));
    });

    test('permits a review verdict when denyOnReview is false', () {
      final permissive = CommandGuard.forSyntax(
        CommandSyntax.bash,
        denyOnReview: false,
      );
      expect(
        permissive.evaluateSync('rm', const ['-rf', '/tmp/foo']).allowed,
        isTrue,
      );
    });
  });

  group('CommandGuard filter (full override)', () {
    test('filter receives the analysis info', () {
      CommandReview? seen;
      final guard = CommandGuard.forSyntax(
        CommandSyntax.bash,
        filter: (review) {
          seen = review;
          return null;
        },
      );
      guard.evaluateSync('echo', const ['hi']);
      expect(seen, isNotNull);
      expect(seen!.executable, 'echo');
      expect(seen!.arguments, const ['hi']);
      expect(seen!.command, 'echo hi');
      expect(seen!.decision, CommandDecision.allow);
    });

    test('filter can force-deny a command command_shield allowed', () {
      final guard = CommandGuard.forSyntax(
        CommandSyntax.bash,
        filter: (review) => CommandDecision.deny,
      );
      expect(guard.evaluateSync('echo', const ['hi']).allowed, isFalse);
    });

    test('filter can force-allow a command command_shield denied', () {
      final guard = CommandGuard.forSyntax(
        CommandSyntax.bash,
        filter: (review) => CommandDecision.allow,
      );
      expect(guard.evaluateSync('rm', const ['-rf', '/']).allowed, isTrue);
    });

    test('returning null keeps the command_shield verdict', () {
      final guard = CommandGuard.forSyntax(
        CommandSyntax.bash,
        filter: (review) => null,
      );
      expect(guard.evaluateSync('rm', const ['-rf', '/']).allowed, isFalse);
      expect(guard.evaluateSync('echo', const ['hi']).allowed, isTrue);
    });
  });

  group('CommandGuard confirm (denial override)', () {
    test('confirm true overrides a denial and flags the outcome', () async {
      CommandReview? seen;
      final guard = CommandGuard.forSyntax(
        CommandSyntax.bash,
        confirm: (review) {
          seen = review;
          return true;
        },
        // Allow confirming even a critical denial for this test.
        neverConfirmCritical: false,
      );
      final outcome = await guard.evaluate('rm', const ['-rf', '/']);
      expect(outcome.allowed, isTrue);
      expect(outcome.overridden, isTrue);
      expect(outcome.reason, contains('confirmed'));
      expect(seen!.executable, 'rm');
    });

    test('confirm false keeps the denial', () async {
      final guard = CommandGuard.forSyntax(
        CommandSyntax.bash,
        confirm: (review) => false,
      );
      final outcome = await guard.evaluate('rm', const ['-rf', '/']);
      expect(outcome.allowed, isFalse);
    });

    test('confirm is not consulted for an allowed command', () async {
      var called = false;
      final guard = CommandGuard.forSyntax(
        CommandSyntax.bash,
        confirm: (review) {
          called = true;
          return true;
        },
      );
      final outcome = await guard.evaluate('echo', const ['hi']);
      expect(outcome.allowed, isTrue);
      expect(outcome.overridden, isFalse);
      expect(called, isFalse);
    });

    test(
      'critical denials cannot be confirmed by default (neverConfirmCritical)',
      () async {
        var called = false;
        final guard = CommandGuard.forSyntax(
          CommandSyntax.bash,
          confirm: (review) {
            called = true;
            return true;
          },
        );
        // `rm -rf /` is classified deny / critical.
        final outcome = await guard.evaluate('rm', const ['-rf', '/']);
        expect(outcome.allowed, isFalse);
        expect(called, isFalse, reason: 'confirm must not be consulted');
        expect(outcome.reason, contains('confirmation disabled'));
      },
    );

    test(
      'neverConfirmCritical: false lets confirm override a critical denial',
      () async {
        final guard = CommandGuard.forSyntax(
          CommandSyntax.bash,
          confirm: (review) => true,
          neverConfirmCritical: false,
        );
        final outcome = await guard.evaluate('rm', const ['-rf', '/']);
        expect(outcome.allowed, isTrue);
        expect(outcome.overridden, isTrue);
      },
    );

    test('a non-critical denial is still confirmable by default', () async {
      // A filter forces a denial on a benign command; that denial is not a
      // critical command_shield classification, so confirm can still override.
      final guard = CommandGuard.forSyntax(
        CommandSyntax.bash,
        filter: (review) => CommandDecision.deny,
        confirm: (review) => true,
      );
      final outcome = await guard.evaluate('echo', const ['hi']);
      expect(outcome.allowed, isTrue);
      expect(outcome.overridden, isTrue);
    });
  });

  group('CommandGuard async callbacks vs runSync', () {
    test('evaluate awaits an async filter', () async {
      final guard = CommandGuard.forSyntax(
        CommandSyntax.bash,
        filter: (review) async => CommandDecision.deny,
      );
      expect((await guard.evaluate('echo', const ['hi'])).allowed, isFalse);
    });

    test('evaluateSync throws on an async filter', () {
      final guard = CommandGuard.forSyntax(
        CommandSyntax.bash,
        filter: (review) async => CommandDecision.deny,
      );
      expect(
        () => guard.evaluateSync('echo', const ['hi']),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('evaluateSync throws on an async confirm of a denied command', () {
      // Use a non-critical (filter-forced) denial so confirm is consulted.
      final guard = CommandGuard.forSyntax(
        CommandSyntax.bash,
        filter: (review) => CommandDecision.deny,
        confirm: (review) async => true,
      );
      expect(
        () => guard.evaluateSync('echo', const ['hi']),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('CommandGuard via Sandbox.process', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('sbx_guard');
    });

    tearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('denies an allowlisted executable used dangerously', () async {
      // `rm` is on the allowlist, so only the command guard can block it. The
      // denial is raised before Process.run, so nothing is ever executed.
      await Sandbox.run(
        root: tempRoot.path,
        policy: const SandboxPolicy(
          allowProcess: true,
          allowedExecutables: ['rm'],
        ),
        commandGuard: CommandGuard.forSyntax(CommandSyntax.bash),
        action: () async {
          await expectLater(
            Sandbox.process.run('rm', const ['-rf', '/']),
            throwsA(isA<SandboxProcessDeniedError>()),
          );
        },
      );
    });

    test('allows a benign command and runs it', () async {
      await Sandbox.run(
        root: tempRoot.path,
        policy: const SandboxPolicy(
          allowProcess: true,
          allowedExecutables: ['echo'],
        ),
        commandGuard: CommandGuard.forSyntax(CommandSyntax.bash),
        action: () async {
          final result = await Sandbox.process.run('echo', const ['hello']);
          expect(result.exitCode, 0);
          expect((result.stdout as String).trim(), 'hello');
        },
      );
    });

    test('a filter can block an otherwise-allowed command', () async {
      await Sandbox.run(
        root: tempRoot.path,
        policy: const SandboxPolicy(
          allowProcess: true,
          allowedExecutables: ['echo'],
        ),
        commandGuard: CommandGuard.forSyntax(
          CommandSyntax.bash,
          filter: (review) => CommandDecision.deny,
        ),
        action: () async {
          await expectLater(
            Sandbox.process.run('echo', const ['hi']),
            throwsA(isA<SandboxProcessDeniedError>()),
          );
        },
      );
    });

    test('runSync throws on an async guard callback', () async {
      await Sandbox.run(
        root: tempRoot.path,
        policy: const SandboxPolicy(
          allowProcess: true,
          allowedExecutables: ['echo'],
        ),
        commandGuard: CommandGuard.forSyntax(
          CommandSyntax.bash,
          filter: (review) async => CommandDecision.deny,
        ),
        action: () async {
          expect(
            () => Sandbox.process.runSync('echo', const ['hi']),
            throwsA(isA<UnsupportedError>()),
          );
        },
      );
    });

    test('emits a denied audit event carrying the guard reason', () async {
      final events = <SandboxAccessEvent>[];
      await Sandbox.run(
        root: tempRoot.path,
        policy: const SandboxPolicy(
          allowProcess: true,
          allowedExecutables: ['rm'],
        ),
        commandGuard: CommandGuard.forSyntax(CommandSyntax.bash),
        onAccess: events.add,
        action: () async {
          try {
            await Sandbox.process.run('rm', const ['-rf', '/']);
          } on SandboxProcessDeniedError {
            // expected
          }
        },
      );
      final denied = events.singleWhere((e) => !e.allowed);
      expect(denied.type, SandboxAccessType.process);
      expect(denied.target, 'rm');
      expect(denied.reason, contains('command_shield'));
    });

    test('without a guard, the allowlist alone governs (baseline)', () async {
      // No commandGuard attached: behaviour is unchanged from allowlist-only.
      // A benign allowlisted command still runs.
      await Sandbox.run(
        root: tempRoot.path,
        policy: const SandboxPolicy(
          allowProcess: true,
          allowedExecutables: ['echo'],
        ),
        action: () async {
          final result = await Sandbox.process.run('echo', const ['hi']);
          expect((result.stdout as String).trim(), 'hi');
        },
      );
    });
  });

  group('CommandGuard nesting', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('sbx_guard_nest');
    });

    tearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('a nested sandbox inherits the parent guard', () async {
      await Sandbox.run(
        root: tempRoot.path,
        policy: const SandboxPolicy(
          allowProcess: true,
          allowedExecutables: ['rm'],
        ),
        commandGuard: CommandGuard.forSyntax(CommandSyntax.bash),
        action: () async {
          Directory('nested').createSync();
          await Sandbox.run(
            root: 'nested',
            policy: const SandboxPolicy(
              allowProcess: true,
              allowedExecutables: ['rm'],
            ),
            action: () async {
              await expectLater(
                Sandbox.process.run('rm', const ['-rf', '/']),
                throwsA(isA<SandboxProcessDeniedError>()),
              );
            },
          );
        },
      );
    });
  });
}
