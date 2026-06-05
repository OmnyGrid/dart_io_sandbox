// Fixture suite: writes a file relative to the sandbox root. Run through
// `bin/dart_io_sandbox.dart` only (see `cli_test.dart`). Passes under a
// read-write preset; fails under `paranoid` (read-only).
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('write inside the jail root', () {
    final f = File('e2e_scratch.txt');
    addTearDown(() {
      if (f.existsSync()) f.deleteSync();
    });
    f.writeAsStringSync('payload');
    expect(f.readAsStringSync(), 'payload');
  });
}
