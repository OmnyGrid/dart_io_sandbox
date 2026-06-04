import 'dart:io';

import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;
  late String root;
  late String realRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('sbx_scenario');
    root = tempRoot.path;
    realRoot = tempRoot.resolveSymbolicLinksSync();
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('Scenario A: file lifecycle stays inside the root', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        final file = File('notes/today.txt');
        await Directory('notes').create(recursive: true);
        await file.writeAsString('content');
        expect(await file.readAsString(), 'content');
        expect(
          p.isWithin(realRoot, file.path) || p.equals(realRoot, file.path),
          isTrue,
        );
      },
    );
    expect(File('$realRoot/notes/today.txt').existsSync(), isTrue);
  });

  test('Scenario B: traversal attack is blocked', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        expect(
          () => File('../../etc/passwd'),
          throwsA(isA<SandboxViolationError>()),
        );
        expect(
          () => File('/etc/passwd'),
          throwsA(isA<SandboxViolationError>()),
        );
      },
    );
  });

  test('Scenario C: allow /safe, deny /safe/secret', () async {
    Directory('$realRoot/safe/secret').createSync(recursive: true);
    await Sandbox.run(
      root: root,
      policy: SandboxPolicy(
        allowedPaths: [p.join(root, 'safe')],
        deniedPaths: [p.join(root, 'safe', 'secret')],
      ),
      action: () async {
        // Allowed.
        await File('safe/ok.txt').writeAsString('fine');
        expect(await File('safe/ok.txt').readAsString(), 'fine');

        // Denied by deny list.
        expect(
          () => File('safe/secret/k.txt').writeAsString('no'),
          throwsA(isA<SandboxPolicyError>()),
        );

        // Outside the allow list.
        expect(
          () => File('elsewhere.txt').writeAsString('no'),
          throwsA(isA<SandboxPolicyError>()),
        );
      },
    );
  });

  test('Scenario D: process execution captures stdout and exit code', () async {
    await Sandbox.run(
      root: root,
      policy: const SandboxPolicy(
        allowProcess: true,
        allowedExecutables: ['echo'],
      ),
      action: () async {
        final result = await Sandbox.process.run('echo', ['hello world']);
        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), 'hello world');
      },
    );
  });

  group('Scenario E: nested sandbox', () {
    test('inner sandbox cannot escape its own root', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          await Directory('inner').create();
          await Sandbox.run(
            root: 'inner',
            action: () async {
              // From inner, the parent is one level up and must be unreachable.
              expect(
                () => File('../outer_secret.txt').writeAsString('x'),
                throwsA(isA<SandboxViolationError>()),
              );
            },
          );
        },
      );
    });

    test('nested root outside the parent is rejected', () async {
      final other = Directory.systemTemp.createTempSync('sbx_other');
      addTearDown(() => other.deleteSync(recursive: true));
      await Sandbox.run(
        root: root,
        action: () async {
          expect(
            () => Sandbox.run(root: other.path, action: () async {}),
            throwsA(isA<SandboxViolationError>()),
          );
        },
      );
    });

    test(
      'nested policy cannot widen the parent (read-only inherited)',
      () async {
        File('$realRoot/inner/f.txt').createSync(recursive: true);
        await Sandbox.run(
          root: root,
          policy: const SandboxPolicy(readOnly: true),
          action: () async {
            await Sandbox.run(
              // Inner asks for read-write, but the parent is read-only.
              root: 'inner',
              policy: const SandboxPolicy(),
              action: () async {
                expect(
                  () => File('f.txt').writeAsString('mutate'),
                  throwsA(isA<SandboxPolicyError>()),
                );
              },
            );
          },
        );
      },
    );
  });

  test('symlink escape is blocked at access time', () async {
    // Create a file outside the sandbox and a symlink inside pointing to it.
    final outside = File('${tempRoot.parent.path}/outside_secret.txt')
      ..writeAsStringSync('top secret');
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync();
    });
    Link('$realRoot/escape').createSync(outside.path);

    await Sandbox.run(
      root: root,
      action: () async {
        // Both constructing and reading through the escaping link must fail.
        expect(
          () => File('escape').readAsString(),
          throwsA(isA<SandboxViolationError>()),
        );
      },
    );
  });

  test('creating an escaping symlink through the sandbox is blocked', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        expect(
          () => Link('bad').createSync('/etc/passwd'),
          throwsA(isA<SandboxViolationError>()),
        );
      },
    );
  });

  test('network access is blocked by default', () async {
    await Sandbox.run(
      root: root,
      action: () async {
        expect(
          () => Socket.connect('example.com', 80),
          throwsA(isA<SandboxViolationError>()),
        );
      },
    );
  });
}
