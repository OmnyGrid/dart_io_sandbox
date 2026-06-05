// End-to-end tests for the `dart_io_sandbox` CLI. Each test invokes
// `bin/dart_io_sandbox.dart` as a subprocess (so it exercises the real command
// dispatch, arg parsing, platform registration and isolate bootstrap) against
// the fixtures in `cli_fixtures/`, then asserts on exit code and output.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final bin = p.join('bin', 'dart_io_sandbox.dart');
  final fixtures = p.join('test', 'integration', 'cli_fixtures');
  final confinement = p.join(fixtures, 'confinement.dart');
  final writable = p.join(fixtures, 'writable.dart');
  final network = p.join(fixtures, 'network.dart');
  final http = p.join(fixtures, 'http.dart');

  Future<ProcessResult> runCli(List<String> args) =>
      Process.run(Platform.resolvedExecutable, ['run', bin, ...args]);

  String combined(ProcessResult r) => '${r.stdout}${r.stderr}';

  Directory tempRoot() => Directory.systemTemp.createTempSync('sbx_e2e');

  // Whether the host can actually reach the internet, used to skip the
  // "network allowed performs a real request" case when offline.
  Future<bool> hasInternet() async {
    try {
      final s = await Socket.connect(
        'example.com',
        443,
        timeout: const Duration(seconds: 5),
      );
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  group('test command', () {
    test('safe preset confines test isolates (escapes denied)', () async {
      final r = await runCli(['test', '-r', 'expanded', confinement]);
      expect(r.exitCode, 0, reason: combined(r));
      expect(r.stdout, contains('All tests passed!'));
    });

    test('safe preset allows writes within the root', () async {
      final root = tempRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      final r = await runCli([
        'test',
        '--root',
        root.path,
        '-r',
        'expanded',
        writable,
      ]);
      expect(r.exitCode, 0, reason: combined(r));
      expect(r.stdout, contains('All tests passed!'));
    });

    test('paranoid preset denies writes (suite fails, exit 1)', () async {
      final root = tempRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      final r = await runCli([
        'test',
        '--preset',
        'paranoid',
        '--root',
        root.path,
        '-r',
        'expanded',
        writable,
      ]);
      expect(r.exitCode, 1, reason: combined(r));
      expect(combined(r), contains('read-only'));
    });

    test('--audit logs access events to stderr', () async {
      final root = tempRoot();
      addTearDown(() => root.deleteSync(recursive: true));
      final r = await runCli([
        'test',
        '--audit',
        '--root',
        root.path,
        '-r',
        'expanded',
        writable,
      ]);
      expect(r.exitCode, 0, reason: combined(r));
      expect(r.stderr, contains('[sandbox]'));
    });

    test('test --help prints sandbox usage without running tests', () async {
      final r = await runCli(['test', '--help']);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('Sandbox options:'));
      expect(r.stdout, contains('Usage: dart_io_sandbox test'));
    });
  });

  group('--no-allow-network', () {
    test('disables network in the test isolates (socket blocked)', () async {
      final r = await runCli([
        'test',
        '--no-allow-network',
        '-r',
        'expanded',
        network,
      ]);
      expect(r.exitCode, 0, reason: combined(r));
      expect(r.stdout, contains('All tests passed!'));
    });

    test(
      'without the flag the safe preset allows network (suite fails)',
      () async {
        // Control: the default `safe` preset has network enabled, so the socket
        // is not blocked and the fixture's SandboxViolationError expectation
        // fails — proving --no-allow-network is what causes the block.
        final r = await runCli(['test', '-r', 'expanded', network]);
        expect(r.exitCode, isNot(0), reason: combined(r));
      },
    );
  });

  group('HttpClient over the network gate', () {
    test('--no-allow-network blocks an HttpClient request', () async {
      // No internet needed: the sandbox gate throws before the socket connects.
      final r = await runCli([
        'test',
        '--no-allow-network',
        '-r',
        'expanded',
        http,
      ]);
      expect(r.exitCode, isNot(0), reason: combined(r));
      expect(
        combined(r),
        contains('network access is disabled by the sandbox policy'),
      );
    });

    test(
      'safe preset (network allowed) performs the real request',
      () async {
        if (!await hasInternet()) {
          markTestSkipped('no network connectivity to example.com:443');
          return;
        }
        final r = await runCli(['test', '-r', 'expanded', http]);
        expect(r.exitCode, 0, reason: combined(r));
        expect(r.stdout, contains('All tests passed!'));
        expect(r.stdout, contains('[network] passed'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('top-level + info commands', () {
    test('no args prints the command list', () async {
      final r = await runCli([]);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('Available commands:'));
      expect(r.stdout, contains('test'));
    });

    test('unknown command exits 64', () async {
      final r = await runCli(['frobnicate']);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('Could not find a command named "frobnicate"'));
    });

    test('presets lists the built-in presets', () async {
      final r = await runCli(['presets']);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('safe'));
      expect(r.stdout, contains('paranoid'));
    });

    test('config prints the resolved configuration', () async {
      final r = await runCli(['config', '--preset', 'paranoid']);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('read_only: true'));
      expect(r.stdout, contains('allow_network: false'));
    });
  });
}
