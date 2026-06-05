import 'package:command_shield/command_shield.dart' show CommandSyntax;
import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  group('SandboxConfig', () {
    test('applies read-write defaults when only a root is given', () {
      const config = SandboxConfig(root: '/some/root');
      expect(config.root, '/some/root');
      expect(config.policy, same(SandboxPolicy.readWrite));
      expect(config.onAccess, isNull);
      expect(config.commandGuard, isNull);
    });

    test('retains the supplied policy, hook and command guard', () {
      final events = <SandboxAccessEvent>[];
      final guard = CommandGuard.forSyntax(CommandSyntax.bash);
      final config = SandboxConfig(
        root: '/r',
        policy: const SandboxPolicy(readOnly: true),
        onAccess: events.add,
        commandGuard: guard,
      );
      expect(config.policy.readOnly, isTrue);
      expect(config.onAccess, isNotNull);
      expect(config.commandGuard, same(guard));
    });
  });
}
