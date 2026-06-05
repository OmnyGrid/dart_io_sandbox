import 'dart:io' as io;

import 'package:command_shield/command_shield.dart';
import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  late io.Directory tempRoot;

  setUp(() {
    tempRoot = io.Directory.systemTemp.createTempSync('sbx_rewrite');
  });
  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  group('applyRewriters', () {
    test('threads each rewriter result into the next, in order', () {
      CommandRewrite? a(String e, List<String> args) =>
          e == 'one' ? CommandRewrite('two', ['a']) : null;
      CommandRewrite? b(String e, List<String> args) =>
          e == 'two' ? CommandRewrite('three', [...args, 'b']) : null;

      final (exe, out) = applyRewriters([a, b], 'one', const []);
      expect(exe, 'three');
      expect(out, ['a', 'b']);
    });

    test('null leaves the command unchanged', () {
      final (exe, out) = applyRewriters(
        [(e, a) => null],
        'git',
        const ['status'],
      );
      expect(exe, 'git');
      expect(out, ['status']);
    });
  });

  group('sandboxCliArgs', () {
    test('reproduces a read-write, networked policy with a guard', () {
      final args = sandboxCliArgs(
        '/jail',
        const SandboxPolicy(
          allowNetwork: true,
          allowProcess: true,
          allowedExecutables: ['dart', 'pub'],
          deniedPaths: ['/jail/secret'],
        ),
        commandGuard: CommandGuard.forSyntax(CommandSyntax.bash),
      );
      expect(args, containsAllInOrder(['--preset', 'none']));
      expect(args, containsAllInOrder(['--root', '/jail']));
      expect(args, contains('--no-read-only'));
      expect(args, contains('--allow-network'));
      expect(args, contains('--allow-process'));
      expect(args, containsAllInOrder(['--allow-exe', 'dart']));
      expect(args, containsAllInOrder(['--allow-exe', 'pub']));
      expect(args, containsAllInOrder(['--deny-path', '/jail/secret']));
      expect(args, contains('--command-guard'));
      expect(args, containsAllInOrder(['--command-guard-syntax', 'bash']));
      expect(args, contains('--command-guard-deny-on-review'));
      expect(args, contains('--command-guard-never-confirm-critical'));
    });

    test('reproduces a locked-down policy with no guard', () {
      final args = sandboxCliArgs('/jail', const SandboxPolicy(readOnly: true));
      expect(args, contains('--read-only'));
      expect(args, contains('--no-allow-network'));
      expect(args, contains('--no-allow-process'));
      expect(args, contains('--no-command-guard'));
      expect(args, isNot(contains('--command-guard')));
    });
  });

  group('rewriteDartTestCommand', () {
    test(
      'rewrites `dart test ...` to `dart run dart_io_sandbox test ...`',
      () async {
        await Sandbox.run(
          root: tempRoot.path,
          policy: const SandboxPolicy(
            allowProcess: true,
            allowedExecutables: ['dart'],
          ),
          action: () async {
            final ctx = Sandbox.current!;
            final r = rewriteDartTestCommand(ctx, 'dart', ['test', '-j', '2']);
            expect(r, isNotNull);
            expect(r!.executable, 'dart');
            expect(r.arguments.take(3), ['run', 'dart_io_sandbox', 'test']);
            // The emitted --root is the canonical (symlink-resolved) realRoot.
            expect(r.arguments, containsAllInOrder(['--root', ctx.realRoot]));
            // Original test-runner args are preserved at the end.
            expect(r.arguments, containsAllInOrder(['-j', '2']));
          },
        );
      },
    );

    test('leaves non-`dart test` commands untouched', () async {
      await Sandbox.run(
        root: tempRoot.path,
        action: () async {
          expect(
            rewriteDartTestCommand(Sandbox.current!, 'git', ['status']),
            isNull,
          );
          expect(
            rewriteDartTestCommand(Sandbox.current!, 'dart', ['pub', 'get']),
            isNull,
          );
          expect(
            rewriteDartTestCommand(Sandbox.current!, 'dart', const []),
            isNull,
          );
        },
      );
    });

    test('honours a custom rewrite prefix (global binary form)', () async {
      await Sandbox.run(
        root: tempRoot.path,
        dartTestRewritePrefix: const ['dart_io_sandbox'],
        action: () async {
          final r = rewriteDartTestCommand(Sandbox.current!, 'dart', ['test']);
          expect(r!.executable, 'dart_io_sandbox');
          expect(r.arguments.first, 'test');
        },
      );
    });
  });
}
