// Fixture suite for the dart_io_sandbox CLI e2e tests. Not named `*_test.dart`
// so the package's own `dart test` run does not pick it up; it is executed only
// through `bin/dart_io_sandbox.dart` by `cli_test.dart`.
import 'dart:io';

import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  test('a sandbox context is installed in the test isolate', () {
    expect(Sandbox.current, isNotNull);
  });

  test('absolute escape outside the root is a SandboxViolationError', () {
    expect(
      () => File('/etc/hosts').readAsStringSync(),
      throwsA(isA<SandboxViolationError>()),
    );
  });
}
