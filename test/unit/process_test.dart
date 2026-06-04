import 'dart:io';

import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('sbx_proc');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('allowed process executes and captures stdout/exit code', () async {
    await Sandbox.run(
      root: tempRoot.path,
      policy: const SandboxPolicy(
        allowProcess: true,
        allowedExecutables: ['echo'],
      ),
      action: () async {
        final result = await Sandbox.process.run('echo', ['hello']);
        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), 'hello');
      },
    );
  });

  test('non-allowlisted executable is denied', () async {
    await Sandbox.run(
      root: tempRoot.path,
      policy: const SandboxPolicy(
        allowProcess: true,
        allowedExecutables: ['echo'],
      ),
      action: () async {
        expect(
          () => Sandbox.process.run('ls', const []),
          throwsA(isA<SandboxProcessDeniedError>()),
        );
      },
    );
  });

  test('process is denied when allowProcess is false', () async {
    await Sandbox.run(
      root: tempRoot.path,
      policy: const SandboxPolicy(allowedExecutables: ['echo']),
      action: () async {
        expect(
          () => Sandbox.process.run('echo', const ['hi']),
          throwsA(isA<SandboxProcessDeniedError>()),
        );
      },
    );
  });

  test('shell metacharacters in arguments are rejected', () async {
    await Sandbox.run(
      root: tempRoot.path,
      policy: const SandboxPolicy(
        allowProcess: true,
        allowedExecutables: ['echo'],
      ),
      action: () async {
        expect(
          () => Sandbox.process.run('echo', const ['a; rm -rf /']),
          throwsA(isA<SandboxProcessDeniedError>()),
        );
      },
    );
  });

  test('process API outside a sandbox throws', () {
    expect(
      () => Sandbox.process.run('echo', const ['hi']),
      throwsA(isA<SandboxProcessDeniedError>()),
    );
  });
}
