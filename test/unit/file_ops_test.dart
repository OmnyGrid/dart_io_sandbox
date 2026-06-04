import 'dart:io';

import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;
  late String root;
  late String realRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('sbx_fileops');
    root = tempRoot.path;
    realRoot = tempRoot.resolveSymbolicLinksSync();
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('write inside sandbox succeeds and lands under root', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        final file = File('data.txt');
        await file.writeAsString('hello');
        expect(await file.readAsString(), 'hello');
        expect(file.path, startsWith(realRoot));
      },
    );
    // Verify on the real filesystem, outside the sandbox.
    final real = File('${tempRoot.resolveSymbolicLinksSync()}/data.txt');
    expect(real.existsSync(), isTrue);
    expect(real.readAsStringSync(), 'hello');
  });

  test('absolute-path write outside sandbox fails at construction', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        expect(() => File('/etc/hosts'), throwsA(isA<SandboxViolationError>()));
      },
    );
  });

  test('../ traversal fails at construction', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        expect(
          () => File('../../etc/passwd'),
          throwsA(isA<SandboxViolationError>()),
        );
      },
    );
  });

  test('read of an allowed file succeeds', () async {
    File('${tempRoot.path}/seed.txt').writeAsStringSync('seeded');
    await Sandbox.run(
      root: root,
      action: () async {
        expect(await File('seed.txt').readAsString(), 'seeded');
      },
    );
  });

  test('delete is blocked in read-only mode', () async {
    File('${tempRoot.path}/keep.txt').writeAsStringSync('x');
    await Sandbox.run(
      root: root,
      policy: const SandboxPolicy(readOnly: true),
      action: () async {
        expect(
          () => File('keep.txt').delete(),
          throwsA(isA<SandboxPolicyError>()),
        );
        // Reads still work.
        expect(await File('keep.txt').readAsString(), 'x');
      },
    );
    // File untouched.
    expect(File('${tempRoot.path}/keep.txt').existsSync(), isTrue);
  });

  test('write is blocked in read-only mode', () async {
    await Sandbox.run(
      root: root,
      policy: const SandboxPolicy(readOnly: true),
      action: () async {
        expect(
          () => File('new.txt').writeAsString('nope'),
          throwsA(isA<SandboxPolicyError>()),
        );
      },
    );
  });

  test(
    'RandomAccessFile open in write mode is blocked in read-only mode',
    () async {
      await Sandbox.run(
        root: root,
        policy: const SandboxPolicy(readOnly: true),
        action: () async {
          expect(
            () => File('w.txt').open(mode: FileMode.write),
            throwsA(isA<SandboxPolicyError>()),
          );
          expect(
            () => File('w.txt').openSync(mode: FileMode.write),
            throwsA(isA<SandboxPolicyError>()),
          );
          expect(
            () => File('w.txt').openWrite(),
            throwsA(isA<SandboxPolicyError>()),
          );
        },
      );
      // Nothing was created.
      expect(File('${tempRoot.path}/w.txt').existsSync(), isFalse);
    },
  );

  test('RandomAccessFile read access is allowed in read-only mode', () async {
    File('${tempRoot.path}/seed.txt').writeAsStringSync('hello');
    await Sandbox.run(
      root: root,
      policy: const SandboxPolicy(readOnly: true),
      action: () async {
        final raf = await File('seed.txt').open();
        addTearDown(raf.close);
        final bytes = await raf.read(5);
        expect(String.fromCharCodes(bytes), 'hello');
        // Streaming read is allowed too.
        final chunks = await File('seed.txt').openRead().toList();
        expect(chunks.expand((c) => c).toList(), 'hello'.codeUnits);
      },
    );
  });

  test('directory listing yields sandboxed, contained entities', () async {
    File('${tempRoot.path}/a.txt').writeAsStringSync('a');
    File('${tempRoot.path}/b.txt').writeAsStringSync('b');
    await Sandbox.run(
      root: root,
      action: () async {
        final entries = Directory('.').listSync();
        expect(entries, hasLength(2));
        for (final e in entries) {
          expect(e.path, startsWith(realRoot));
        }
      },
    );
  });

  test('rename within the sandbox works and stays contained', () async {
    File('${tempRoot.path}/src.txt').writeAsStringSync('data');
    await Sandbox.run(
      root: root,
      action: () async {
        final moved = await File('src.txt').rename('dst.txt');
        expect(await moved.readAsString(), 'data');
      },
    );
    expect(File('${tempRoot.path}/dst.txt').existsSync(), isTrue);
  });

  test('rename to a path outside the sandbox fails', () async {
    File('${tempRoot.path}/src.txt').writeAsStringSync('data');
    await Sandbox.run(
      root: root,
      action: () async {
        expect(
          () => File('src.txt').rename('../escape.txt'),
          throwsA(isA<SandboxViolationError>()),
        );
      },
    );
  });

  test('access hook observes allow and deny events', () async {
    final events = <SandboxAccessEvent>[];
    await Sandbox.run(
      root: root,
      policy: const SandboxPolicy(readOnly: true),
      onAccess: events.add,
      action: () async {
        await File('r.txt').exists();
        expect(
          () => File('w.txt').writeAsString('x'),
          throwsA(isA<SandboxPolicyError>()),
        );
      },
    );
    expect(events.any((e) => e.allowed), isTrue);
    expect(events.any((e) => !e.allowed), isTrue);
  });
}
