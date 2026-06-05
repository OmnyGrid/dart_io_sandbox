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

  test('SandboxFileSystem.fromConfig confines like .bound', () async {
    final fs = SandboxFileSystem.fromConfig(
      SandboxConfig(root: tempRoot.path),
    );
    await fs.file('cfg.txt').writeAsString('from config');
    expect(await fs.file('cfg.txt').readAsString(), 'from config');
    expect(
      () => fs.file('../../etc/passwd'),
      throwsA(isA<SandboxViolationError>()),
    );
  });

  test('directory() and link() are confined', () async {
    final fs = SandboxFileSystem.bound(root: tempRoot.path);
    await fs.directory('d').create();
    expect(await fs.directory('d').exists(), isTrue);
    expect(
      () => fs.directory('../../tmp'),
      throwsA(isA<SandboxViolationError>()),
    );
    await fs.file('t.txt').writeAsString('x');
    await fs.link('l.lnk').create('t.txt');
    expect(await fs.link('l.lnk').target(), 't.txt');
  });

  test('stat / type / identical run inside the bound sandbox', () async {
    final fs = SandboxFileSystem.bound(root: tempRoot.path);
    await fs.file('a.txt').writeAsString('x');

    final stat = await fs.stat('a.txt');
    expect(stat.type, io.FileSystemEntityType.file);
    expect(fs.statSync('a.txt').type, io.FileSystemEntityType.file);

    // type/typeSync execute through the bound zone; just exercise the surface.
    expect(await fs.type('a.txt'), isA<io.FileSystemEntityType>());
    expect(fs.typeSync('a.txt'), isA<io.FileSystemEntityType>());

    final real = tempRoot.resolveSymbolicLinksSync();
    expect(await fs.identical('$real/a.txt', '$real/a.txt'), isTrue);
    expect(fs.identicalSync('$real/a.txt', '$real/a.txt'), isTrue);
  });

  test('currentDirectory and systemTempDirectory resolve in the root', () {
    final fs = SandboxFileSystem.bound(root: tempRoot.path);
    final real = tempRoot.resolveSymbolicLinksSync();
    expect(fs.currentDirectory.path, startsWith(real));
    // getSystemTempDirectory is redirected to a `.tmp` dir inside the root.
    expect(fs.systemTempDirectory.path, startsWith(real));
  });
}
