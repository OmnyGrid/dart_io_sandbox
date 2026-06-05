import 'dart:io';

import 'package:command_shield/command_shield.dart';
import 'package:dart_io_sandbox/src/cli/config_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  const cwd = '/work/pkg';

  group('resolveConfig presets', () {
    test('safe is the default preset', () {
      final c = resolveConfig(const SandboxCliOverrides(), cwd: cwd);
      expect(c.readOnly, isFalse);
      expect(c.allowNetwork, isTrue);
      expect(c.allowProcess, isTrue);
      expect(c.allowedExecutables, ['dart', 'flutter', 'pub']);
      expect(c.commandGuard.enabled, isTrue);
      expect(c.commandGuard.syntax, CommandSyntax.bash);
      expect(c.root, p.normalize(cwd));
    });

    test('paranoid preset is locked down', () {
      final c = resolveConfig(
        const SandboxCliOverrides(preset: 'paranoid'),
        cwd: cwd,
      );
      expect(c.readOnly, isTrue);
      expect(c.allowNetwork, isFalse);
      expect(c.allowProcess, isFalse);
      expect(c.commandGuard.enabled, isFalse);
    });

    test('unknown preset throws', () {
      expect(
        () =>
            resolveConfig(const SandboxCliOverrides(preset: 'nope'), cwd: cwd),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('root resolution', () {
    test('relative root resolves against cwd', () {
      final c = resolveConfig(
        const SandboxCliOverrides(root: 'sub/dir'),
        cwd: cwd,
      );
      expect(c.root, p.normalize(p.join(cwd, 'sub/dir')));
    });

    test('absolute root is kept', () {
      final c = resolveConfig(
        const SandboxCliOverrides(root: '/abs/root'),
        cwd: cwd,
      );
      expect(c.root, '/abs/root');
    });
  });

  group('precedence: preset < yaml < cli', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sbx_cfg'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('yaml overrides preset', () {
      final f = File(p.join(tmp.path, 'sandbox.yaml'))
        ..writeAsStringSync('''
preset: safe
allow_network: false
allowed_executables: [dart]
command_guard:
  enabled: true
  syntax: generic
  deny_on_review: false
''');
      final c = resolveConfig(
        SandboxCliOverrides(configPath: f.path),
        cwd: cwd,
      );
      expect(c.allowNetwork, isFalse); // overridden
      expect(c.allowProcess, isTrue); // from preset
      expect(c.allowedExecutables, ['dart']); // overridden
      expect(c.commandGuard.syntax, CommandSyntax.generic);
      expect(c.commandGuard.denyOnReview, isFalse);
    });

    test('cli overrides yaml', () {
      final f = File(p.join(tmp.path, 'sandbox.yaml'))
        ..writeAsStringSync('allow_network: false\n');
      final c = resolveConfig(
        SandboxCliOverrides(configPath: f.path, allowNetwork: true),
        cwd: cwd,
      );
      expect(c.allowNetwork, isTrue);
    });

    test('cli list flags add on top of preset/yaml', () {
      final c = resolveConfig(
        const SandboxCliOverrides(allowedExecutables: ['git']),
        cwd: cwd,
      );
      expect(c.allowedExecutables, ['dart', 'flutter', 'pub', 'git']);
    });

    test('missing config file throws', () {
      expect(
        () => resolveConfig(
          const SandboxCliOverrides(configPath: '/no/such.yaml'),
          cwd: cwd,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
