// End-to-end proof that an intercepted `dart test` run through Sandbox.process
// is rewritten to a sandboxed `dart run dart_io_sandbox test` invocation.
//
// The `confinement.dart` fixture asserts `Sandbox.current != null`, which only
// holds when it runs under `dart_io_sandbox`. So a passing nested run proves the
// rewrite fired and re-established the jail in the child process; a plain
// `dart test` (rewrite disabled) fails that assertion.
import 'dart:io';

import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final confinement = p.join(
    'test',
    'integration',
    'cli_fixtures',
    'confinement.dart',
  );
  // The sandbox root is this package dir, so `dart run dart_io_sandbox` resolves.
  final root = Directory.current.path;
  // Absolute path; its basename is still `dart`, matching the allowlist + the
  // rewrite trigger.
  final dart = Platform.resolvedExecutable;

  Future<ProcessResult> runUnderSandbox({required bool rewrite}) => Sandbox.run(
    root: root,
    rewriteDartTest: rewrite,
    policy: const SandboxPolicy(
      allowProcess: true,
      allowNetwork: true,
      allowedExecutables: ['dart'],
    ),
    action: () =>
        Sandbox.process.run(dart, ['test', confinement, '-r', 'compact']),
  );

  test(
    'rewrites `dart test` to a sandboxed dart_io_sandbox run',
    () async {
      final r = await runUnderSandbox(rewrite: true);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout, contains('All tests passed!'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'with rewriteDartTest: false the nested run is NOT sandboxed',
    () async {
      final r = await runUnderSandbox(rewrite: false);
      // Plain `dart test`: the fixture's "sandbox context is installed" test
      // fails, so the suite fails.
      expect(r.exitCode, isNot(0), reason: '${r.stdout}${r.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
