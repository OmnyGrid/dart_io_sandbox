import 'dart:io';

import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;
  late String root;
  late String realRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('sbx_fsextra');
    root = tempRoot.path;
    realRoot = tempRoot.resolveSymbolicLinksSync();
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  group('File copy', () {
    test('copy keeps the duplicate contained and intact', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          await File('src.txt').writeAsString('content');
          final dup = await File('src.txt').copy('dup.txt');
          expect(dup.path, startsWith(realRoot));
          expect(await dup.readAsString(), 'content');
        },
      );
      expect(File('$realRoot/dup.txt').existsSync(), isTrue);
    });

    test('copySync works and a copy out of the root is rejected', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          File('src.txt').writeAsStringSync('c');
          final dup = File('src.txt').copySync('dup2.txt');
          expect(dup.readAsStringSync(), 'c');
          expect(
            () => File('src.txt').copySync('../escape.txt'),
            throwsA(isA<SandboxViolationError>()),
          );
        },
      );
    });
  });

  group('File metadata', () {
    test('length / lengthSync report the byte size', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          await File('f.txt').writeAsString('hello'); // 5 bytes
          expect(await File('f.txt').length(), 5);
          expect(File('f.txt').lengthSync(), 5);
        },
      );
    });

    test('stat / statSync expose entity metadata', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          await File('f.txt').writeAsString('x');
          final s = await File('f.txt').stat();
          expect(s.type, FileSystemEntityType.file);
          expect(File('f.txt').statSync().type, FileSystemEntityType.file);
        },
      );
    });

    test('lastModified can be read and set', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          final file = File('f.txt');
          await file.writeAsString('x');
          final when = DateTime(2020, 1, 2, 3, 4, 5);
          await file.setLastModified(when);
          expect((await file.lastModified()).year, 2020);
          file.setLastModifiedSync(when);
          expect(file.lastModifiedSync().year, 2020);
        },
      );
    });

    test('setLastModified is blocked in read-only mode', () async {
      File('$root/f.txt').writeAsStringSync('x');
      await Sandbox.run(
        root: root,
        policy: const SandboxPolicy(readOnly: true),
        action: () async {
          expect(
            () => File('f.txt').setLastModified(DateTime(2020)),
            throwsA(isA<SandboxPolicyError>()),
          );
        },
      );
    });
  });

  group('File content variants', () {
    test('readAsLines / readAsBytes round-trip', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          await File('f.txt').writeAsString('a\nb\nc');
          expect(await File('f.txt').readAsLines(), ['a', 'b', 'c']);
          expect(File('f.txt').readAsLinesSync(), ['a', 'b', 'c']);
          expect(await File('f.txt').readAsBytes(), 'a\nb\nc'.codeUnits);
          expect(File('f.txt').readAsBytesSync(), 'a\nb\nc'.codeUnits);
        },
      );
    });

    test('writeAsBytes and append via openWrite', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          await File('f.txt').writeAsBytes('hi'.codeUnits);
          final sink = File('f.txt').openWrite(mode: FileMode.append);
          sink.write('!');
          await sink.close();
          expect(await File('f.txt').readAsString(), 'hi!');
        },
      );
    });

    test('writeAsBytesSync writes raw bytes', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          File('f.txt').writeAsBytesSync([104, 105]);
          expect(File('f.txt').readAsStringSync(), 'hi');
        },
      );
    });
  });

  group('FileSystemEntity surface', () {
    test('exists / existsSync reflect presence', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          expect(await File('missing.txt').exists(), isFalse);
          expect(File('missing.txt').existsSync(), isFalse);
          await File('there.txt').writeAsString('x');
          expect(await File('there.txt').exists(), isTrue);
          expect(File('there.txt').existsSync(), isTrue);
        },
      );
    });

    test('parent never walks above the root', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          // The parent of the root is clamped back to the root.
          final rootParent = Directory('.').parent;
          expect(rootParent.path, realRoot);
          // A nested entity reports its real parent (still contained).
          Directory('sub').createSync();
          final nestedParent = File('sub/x.txt').parent;
          expect(nestedParent.path, startsWith(realRoot));
        },
      );
    });

    test('absolute and isAbsolute on sandboxed entities', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          final file = File('a.txt');
          expect(file.isAbsolute, isTrue);
          expect(file.absolute.path, file.path);
          expect(file.uri.scheme, 'file');
        },
      );
    });

    test('toString labels the sandboxed entity kind', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          expect(File('a.txt').toString(), startsWith('SandboxFile:'));
          expect(Directory('d').toString(), startsWith('SandboxDirectory:'));
        },
      );
    });
  });

  group('Directory operations', () {
    test('createTemp creates a contained temp dir', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          final t1 = await Directory('.').createTemp('pre');
          expect(t1.path, startsWith(realRoot));
          final t2 = Directory('.').createTempSync('pre');
          expect(t2.path, startsWith(realRoot));
        },
      );
    });

    test('async list yields contained, sandboxed entities', () async {
      File('$root/a.txt').writeAsStringSync('a');
      Directory('$root/sub').createSync();
      await Sandbox.run(
        root: root,
        action: () async {
          final entries = await Directory('.').list().toList();
          expect(entries, hasLength(2));
          for (final e in entries) {
            expect(e.path, startsWith(realRoot));
          }
          expect(entries.whereType<Directory>(), hasLength(1));
        },
      );
    });

    test('recursive create and rename stay within the root', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          await Directory('a/b/c').create(recursive: true);
          expect(Directory('a/b/c').existsSync(), isTrue);
          final moved = await Directory('a').rename('z');
          expect(moved.path, startsWith(realRoot));
          expect(Directory('z/b/c').existsSync(), isTrue);
        },
      );
    });
  });
}
