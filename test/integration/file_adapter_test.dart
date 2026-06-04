import 'dart:io' as io;

import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:file/file.dart' show FileSystem;
import 'package:test/test.dart';

void main() {
  late io.Directory tempRoot;

  setUp(() {
    tempRoot = io.Directory.systemTemp.createTempSync('sbx_adapter');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('bound SandboxFileSystem confines reads/writes', () async {
    final FileSystem fs = SandboxFileSystem.bound(root: tempRoot.path);

    final file = fs.file('hello.txt');
    await file.writeAsString('via package:file');
    expect(await file.readAsString(), 'via package:file');

    final real = io.File('${tempRoot.resolveSymbolicLinksSync()}/hello.txt');
    expect(real.existsSync(), isTrue);
  });

  test('bound SandboxFileSystem blocks traversal', () {
    final fs = SandboxFileSystem.bound(root: tempRoot.path);
    expect(
      () => fs.file('../../etc/passwd'),
      throwsA(isA<SandboxViolationError>()),
    );
  });

  test('bound SandboxFileSystem enforces read-only policy', () async {
    final fs = SandboxFileSystem.bound(
      root: tempRoot.path,
      policy: const SandboxPolicy(readOnly: true),
    );
    expect(
      () => fs.file('x.txt').writeAsString('nope'),
      throwsA(isA<SandboxPolicyError>()),
    );
  });

  test('ambient SandboxFileSystem is confined inside Sandbox.run', () async {
    await Sandbox.run(
      root: tempRoot.path,
      action: () async {
        final fs = SandboxFileSystem();
        await fs.file('a.txt').writeAsString('ambient');
        expect(await fs.file('a.txt').readAsString(), 'ambient');
        expect(
          () => fs.file('/etc/passwd'),
          throwsA(isA<SandboxViolationError>()),
        );
      },
    );
  });
}
