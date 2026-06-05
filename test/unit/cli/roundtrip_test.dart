// Guards against drift between `sandboxCliArgs` (the config→flags converter) and
// the CLI's flag parsing + config resolution: the flags a sandbox emits must
// parse back into an equivalent configuration.
import 'package:command_shield/command_shield.dart';
import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:dart_io_sandbox/src/cli/args.dart';
import 'package:dart_io_sandbox/src/cli/config_loader.dart';
import 'package:test/test.dart';

void main() {
  void roundTrip(SandboxPolicy policy, {CommandGuard? guard}) {
    const root = '/abs/jail';
    // The CLI dispatcher strips the `test` command name; parseArgs sees the
    // flags that follow it.
    final args = sandboxCliArgs(root, policy, commandGuard: guard);
    final parsed = parseArgs(args);
    expect(parsed.testArgs, isEmpty, reason: 'all flags should be consumed');

    final cfg = resolveConfig(parsed.sandbox, cwd: '/somewhere/else');
    expect(cfg.root, root);
    expect(cfg.readOnly, policy.readOnly);
    expect(cfg.allowNetwork, policy.allowNetwork);
    expect(cfg.allowProcess, policy.allowProcess);
    expect(cfg.allowedExecutables, policy.allowedExecutables);
    expect(cfg.allowedPaths, policy.allowedPaths);
    expect(cfg.deniedPaths, policy.deniedPaths);

    if (guard == null) {
      expect(cfg.commandGuard.enabled, isFalse);
    } else {
      expect(cfg.commandGuard.enabled, isTrue);
      expect(cfg.commandGuard.syntax, guard.shield.defaultSyntax);
      expect(cfg.commandGuard.denyOnReview, guard.denyOnReview);
      expect(cfg.commandGuard.neverConfirmCritical, guard.neverConfirmCritical);
    }
  }

  test('locked-down policy round-trips', () {
    roundTrip(const SandboxPolicy(readOnly: true));
  });

  test('permissive policy with lists round-trips', () {
    roundTrip(
      const SandboxPolicy(
        allowNetwork: true,
        allowProcess: true,
        allowedExecutables: ['dart', 'flutter', 'pub'],
        allowedPaths: ['/abs/jail/a'],
        deniedPaths: ['/abs/jail/secret'],
      ),
    );
  });

  test('policy + bash guard round-trips', () {
    roundTrip(
      const SandboxPolicy(allowProcess: true, allowedExecutables: ['dart']),
      guard: CommandGuard.forSyntax(CommandSyntax.bash),
    );
  });

  test('policy + posix guard with non-default flags round-trips', () {
    roundTrip(
      const SandboxPolicy(),
      guard: CommandGuard.forSyntax(
        CommandSyntax.posixShell,
        denyOnReview: false,
        neverConfirmCritical: false,
      ),
    );
  });
}
