// Fixture suite for the dart_io_sandbox CLI e2e tests. Not named `*_test.dart`
// so the package's own `dart test` run does not pick it up; it is executed only
// through `bin/dart_io_sandbox.dart` by `cli_test.dart`.
//
// Asserts that socket creation is blocked by the sandbox. This passes only when
// the test isolate runs with `allowNetwork: false` (e.g. `--no-allow-network`);
// the sandbox's network gate throws synchronously before any real I/O, so
// `127.0.0.1:9` is never actually contacted.
import 'dart:io';

import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  test('socket creation is blocked when network is disabled', () {
    expect(
      () => Socket.connect('127.0.0.1', 9),
      throwsA(isA<SandboxViolationError>()),
    );
  });
}
