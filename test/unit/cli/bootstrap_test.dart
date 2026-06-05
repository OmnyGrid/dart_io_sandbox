import 'package:command_shield/command_shield.dart';
import 'package:dart_io_sandbox/src/cli/bootstrap.dart';
import 'package:dart_io_sandbox/src/cli/sandbox_test_config.dart';
import 'package:test/test.dart';

void main() {
  final testUri = Uri.parse('file:///work/pkg/test/foo_test.dart');

  String gen(SandboxTestConfig config) =>
      generateBootstrap(config: config, testUri: testUri);

  test('wraps the standard bootstrap in Sandbox.run', () {
    final src = gen(const SandboxTestConfig(root: '/jail'));
    expect(src, contains('Sandbox.run('));
    expect(src, contains("import '$testUri' as test;"));
    expect(
      src,
      contains('internalBootstrapVmTest(() => test.main, sendPort);'),
    );
    expect(src, contains("root: '/jail'"));
  });

  test('emits the policy as literals', () {
    final src = gen(
      const SandboxTestConfig(
        root: '/jail',
        readOnly: true,
        allowNetwork: true,
        allowProcess: true,
        allowedExecutables: ['dart', 'pub'],
        deniedPaths: ['secret'],
      ),
    );
    expect(src, contains('readOnly: true'));
    expect(src, contains('allowNetwork: true'));
    expect(src, contains('allowProcess: true'));
    expect(src, contains("allowedExecutables: ['dart', 'pub']"));
    expect(src, contains("deniedPaths: ['secret']"));
  });

  test('emits a CommandGuard when enabled, null otherwise', () {
    final withGuard = gen(
      const SandboxTestConfig(
        root: '/jail',
        commandGuard: CommandGuardConfig(
          enabled: true,
          syntax: CommandSyntax.bash,
          denyOnReview: true,
          neverConfirmCritical: true,
        ),
      ),
    );
    expect(
      withGuard,
      contains(
        'CommandGuard.forSyntax(CommandSyntax.bash, '
        'denyOnReview: true, neverConfirmCritical: true)',
      ),
    );

    final noGuard = gen(const SandboxTestConfig(root: '/jail'));
    expect(noGuard, contains('commandGuard: null'));
  });

  test('audit block present only when enabled', () {
    expect(
      gen(const SandboxTestConfig(root: '/jail', audit: true)),
      contains('onAccess:'),
    );
    expect(
      gen(const SandboxTestConfig(root: '/jail', audit: false)),
      isNot(contains('onAccess:')),
    );
  });

  test('escapes quotes and backslashes in the root path', () {
    final src = gen(const SandboxTestConfig(root: r"/a'b\c"));
    expect(src, contains(r"root: '/a\'b\\c'"));
  });
}
