import 'dart:io';

import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;
  late String root;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('sbx_link');
    root = tempRoot.path;
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('create a link to a target inside the root and read it back', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        await File('target.txt').writeAsString('payload');
        final link = Link('alias.lnk');
        await link.create('target.txt');
        expect(await link.target(), 'target.txt');
        // Reading through the link resolves to the target's content.
        expect(await File('alias.lnk').readAsString(), 'payload');
      },
    );
  });

  test('createSync / targetSync round-trips inside the root', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        File('t.txt').writeAsStringSync('x');
        final link = Link('s.lnk')..createSync('t.txt');
        expect(link.targetSync(), 't.txt');
      },
    );
  });

  test('creating a link whose target escapes the root is rejected', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        final link = Link('escape.lnk');
        await expectLater(
          link.create('../../etc/passwd'),
          throwsA(isA<SandboxViolationError>()),
        );
        expect(
          () => link.createSync('/etc/passwd'),
          throwsA(isA<SandboxViolationError>()),
        );
      },
    );
  });

  test('updating a link to an escaping target is rejected', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        File('a.txt').writeAsStringSync('a');
        File('b.txt').writeAsStringSync('b');
        final link = Link('l.lnk')..createSync('a.txt');
        // A contained update is fine.
        await link.update('b.txt');
        expect(await link.target(), 'b.txt');
        // An escaping update throws.
        await expectLater(
          link.update('../../outside'),
          throwsA(isA<SandboxViolationError>()),
        );
        expect(
          () => link.updateSync('/tmp/outside'),
          throwsA(isA<SandboxViolationError>()),
        );
      },
    );
  });

  test('renaming a link stays contained and keeps its target', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        File('t.txt').writeAsStringSync('x');
        final link = Link('old.lnk')..createSync('t.txt');
        final moved = await link.rename('new.lnk');
        expect(moved, isA<Link>());
        expect(await (moved).target(), 't.txt');
      },
    );
  });

  test('renaming a link outside the root is rejected', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        File('t.txt').writeAsStringSync('x');
        final link = Link('l.lnk')..createSync('t.txt');
        expect(
          () => link.renameSync('../escaped.lnk'),
          throwsA(isA<SandboxViolationError>()),
        );
      },
    );
  });

  test('link entity exposes a sandboxed path and toString', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        File('t.txt').writeAsStringSync('x');
        final link = Link('l.lnk')..createSync('t.txt');
        expect(link.isAbsolute, isTrue);
        expect(link.absolute, isA<Link>());
        expect(link.toString(), startsWith('SandboxLink:'));
      },
    );
  });
}
