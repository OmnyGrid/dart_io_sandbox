// Reproduces the standalone/global-install failure of `dart_io_sandbox test`.
//
// When `dart_io_sandbox` is installed standalone (e.g. `dart pub global activate
// dart_io_sandbox`) and run against a *separate* project that only declares
// `test` as a dev_dependency (and does NOT depend on `dart_io_sandbox`), every
// test isolate is spawned with the CLI's own package config rather than the
// target project's. That config — being a non-dev resolution of
// `dart_io_sandbox` — has no `test` entry (it is a dev_dependency of
// dart_io_sandbox), so the target test file's `import 'package:test/test.dart'`
// fails to resolve at isolate load time.
//
// Root cause: `SandboxVMPlatform._spawnIsolate` spawns with
// `packageConfig: await packageConfigUri`, and `packageConfigUri` is just
// `Isolate.packageConfig` (the CLI process's config), never the target
// project's `.dart_tool/package_config.json`.
//
// This test recreates that environment deterministically, without mutating the
// user's global pub cache: it builds a dev-stripped package config by running
// `dart pub get` on a throwaway consumer that path-depends on this repo, then
// launches the CLI with `--packages=<that config>`.
//
// Fixed: `SandboxVMPlatform` now spawns each suite isolate with a package config
// that merges the project-under-test's resolution with the sandbox packages the
// bootstrap needs (see `lib/src/cli/package_config_merge.dart`). This test is
// the regression guard for that fix.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final dart = Platform.resolvedExecutable;
  final repoRoot = Directory.current.path;
  final bin = p.join(repoRoot, 'bin', 'dart_io_sandbox.dart');

  String combined(ProcessResult r) => '${r.stdout}${r.stderr}';

  /// Runs `dart pub get` in [dir]. Returns the result so callers can skip the
  /// test (rather than hard-fail) when resolution needs the network and the
  /// host is offline.
  Future<ProcessResult> pubGet(Directory dir) =>
      Process.run(dart, ['pub', 'get'], workingDirectory: dir.path);

  group('standalone install (CLI does not share the target package config)', () {
    // The dev-stripped package config that mimics a global/standalone install:
    // a throwaway consumer that path-depends on this repo. Its
    // package_config.json includes dart_io_sandbox + command_shield +
    // test_core/test_api (and transitive deps) but NOT `test`.
    late String cliPackageConfig;
    // The separate project under test: only `test` as a dev_dependency.
    late Directory target;

    setUpAll(() async {
      final consumer = Directory.systemTemp.createTempSync('sbx_cli_install');
      addTearDown(() {
        if (consumer.existsSync()) consumer.deleteSync(recursive: true);
      });
      File(p.join(consumer.path, 'pubspec.yaml')).writeAsStringSync('''
name: sbx_cli_consumer
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  dart_io_sandbox:
    path: ${repoRoot.replaceAll(r'\', '/')}
''');
      final consumerGet = await pubGet(consumer);
      if (consumerGet.exitCode != 0) {
        markTestSkipped(
          'could not `pub get` the dart_io_sandbox consumer '
          '(offline?):\n${combined(consumerGet)}',
        );
        return;
      }
      cliPackageConfig = p.join(
        consumer.path,
        '.dart_tool',
        'package_config.json',
      );

      target = Directory.systemTemp.createTempSync('sbx_repro_target');
      addTearDown(() {
        if (target.existsSync()) target.deleteSync(recursive: true);
      });
      File(p.join(target.path, 'pubspec.yaml')).writeAsStringSync('''
name: repro_target
publish_to: none
environment:
  sdk: ^3.10.0
dev_dependencies:
  test: ^1.25.6
''');
      final testDir = Directory(p.join(target.path, 'test'))
        ..createSync(recursive: true);
      File(p.join(testDir.path, 'sample_test.dart')).writeAsStringSync('''
import 'package:test/test.dart';

void main() {
  test('trivial', () {
    expect(1 + 1, 2);
  });
}
''');
      final targetGet = await pubGet(target);
      if (targetGet.exitCode != 0) {
        markTestSkipped(
          'could not `pub get` the target project '
          '(offline?):\n${combined(targetGet)}',
        );
        return;
      }
    });

    test(
      'control: plain `dart test` in the target project passes',
      () async {
        // Force the `expanded` reporter so the output is deterministic: under
        // GitHub Actions the runner defaults to the `github` reporter, which
        // prints "🎉 1 test passed." instead of "All tests passed!".
        final r = await Process.run(dart, [
          'test',
          '-r',
          'expanded',
          p.join('test', 'sample_test.dart'),
        ], workingDirectory: target.path);
        expect(r.exitCode, 0, reason: combined(r));
        expect(r.stdout, contains('All tests passed!'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('regression: `dart_io_sandbox test` resolves package:test from the '
        'project under test even when the CLI config lacks it', () async {
      final r = await Process.run(dart, [
        'run',
        '--packages=$cliPackageConfig',
        bin,
        'test',
        '-r',
        'expanded',
        p.join('test', 'sample_test.dart'),
      ], workingDirectory: target.path);
      final out = combined(r);
      // The spawned isolate now uses a config that merges the project's
      // resolution (which has `test`) with the CLI's sandbox packages, so the
      // suite loads and passes.
      expect(r.exitCode, 0, reason: out);
      expect(r.stdout, contains('All tests passed!'), reason: out);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
