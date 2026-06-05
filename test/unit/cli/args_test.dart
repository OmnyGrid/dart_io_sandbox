import 'package:dart_io_sandbox/src/cli/args.dart';
import 'package:test/test.dart';

void main() {
  group('parseArgs splitting', () {
    test('separates sandbox flags from forwarded test args', () {
      final parsed = parseArgs([
        '--preset',
        'paranoid',
        '--root',
        '/jail',
        'test/foo_test.dart',
        '-j',
        '4',
        '--allow-exe',
        'git',
        '-n',
        'my group',
      ]);

      expect(parsed.sandbox.preset, 'paranoid');
      expect(parsed.sandbox.root, '/jail');
      expect(parsed.sandbox.allowedExecutables, ['git']);
      // Everything the sandbox does not own is forwarded verbatim, in order.
      expect(parsed.testArgs, [
        'test/foo_test.dart',
        '-j',
        '4',
        '-n',
        'my group',
      ]);
    });

    test('supports --opt=value form', () {
      final parsed = parseArgs(['--root=/x', '--preset=safe', 'a_test.dart']);
      expect(parsed.sandbox.root, '/x');
      expect(parsed.sandbox.preset, 'safe');
      expect(parsed.testArgs, ['a_test.dart']);
    });

    test('negatable flags map to true/false/null', () {
      final on = parseArgs(['--allow-network', '--read-only', '--audit']);
      expect(on.sandbox.allowNetwork, isTrue);
      expect(on.sandbox.readOnly, isTrue);
      expect(on.sandbox.audit, isTrue);

      final off = parseArgs(['--no-allow-network', '--no-allow-process']);
      expect(off.sandbox.allowNetwork, isFalse);
      expect(off.sandbox.allowProcess, isFalse);

      final absent = parseArgs(['test/']);
      expect(absent.sandbox.allowNetwork, isNull);
      expect(absent.sandbox.readOnly, isNull);
      expect(absent.sandbox.audit, isNull);
    });

    test('repeatable list options accumulate', () {
      final parsed = parseArgs([
        '--allow-path',
        'a',
        '--allow-path',
        'b',
        '--deny-path',
        'secret',
      ]);
      expect(parsed.sandbox.allowedPaths, ['a', 'b']);
      expect(parsed.sandbox.deniedPaths, ['secret']);
    });

    test('command-guard flags parse (and are not forwarded)', () {
      final parsed = parseArgs([
        '--command-guard',
        '--command-guard-syntax',
        'bash',
        '--no-command-guard-deny-on-review',
        '--command-guard-never-confirm-critical',
        'test/foo_test.dart',
      ]);
      expect(parsed.sandbox.commandGuard, isTrue);
      expect(parsed.sandbox.commandGuardSyntax, 'bash');
      expect(parsed.sandbox.commandGuardDenyOnReview, isFalse);
      expect(parsed.sandbox.commandGuardNeverConfirmCritical, isTrue);
      expect(parsed.testArgs, ['test/foo_test.dart']);
    });

    test('-h / --help is captured and not forwarded', () {
      expect(parseArgs(['-h']).help, isTrue);
      expect(parseArgs(['--help', 'test/']).help, isTrue);
      expect(parseArgs(['--help', 'test/']).testArgs, ['test/']);
    });

    test('empty argv yields empty forwarded args', () {
      final parsed = parseArgs([]);
      expect(parsed.testArgs, isEmpty);
      expect(parsed.help, isFalse);
    });
  });
}
