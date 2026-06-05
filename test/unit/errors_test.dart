import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  group('SandboxError hierarchy', () {
    test('all sandbox errors are Errors, not Exceptions', () {
      expect(SandboxViolationError('/x', 'r'), isA<Error>());
      expect(SandboxPathError('/x', 'r'), isA<SandboxError>());
      expect(SandboxPolicyError('/x', 'r'), isA<SandboxError>());
      expect(SandboxProcessDeniedError('echo', 'r'), isA<SandboxError>());
    });

    test('carries the attempted path/action and reason', () {
      final err = SandboxPolicyError('/root/secret', 'covered by deny list');
      expect(err.attempted, '/root/secret');
      expect(err.reason, 'covered by deny list');
    });
  });

  group('labels and toString', () {
    test('each error exposes its stable label', () {
      expect(SandboxViolationError('/x', 'r').label, 'SandboxViolation');
      expect(SandboxPathError('/x', 'r').label, 'SandboxPathError');
      expect(SandboxPolicyError('/x', 'r').label, 'SandboxPolicyError');
      expect(SandboxProcessDeniedError('e', 'r').label, 'SandboxProcessDenied');
    });

    test('toString combines label, reason and attempted', () {
      final err = SandboxViolationError('/etc/passwd', 'escapes root');
      expect(
        err.toString(),
        'SandboxViolation: escapes root (attempted: "/etc/passwd")',
      );
    });
  });

  group('SandboxViolationError factories', () {
    test('escape() builds a root-escape reason', () {
      final err = SandboxViolationError.escape('../x', '/root');
      expect(err.attempted, '../x');
      expect(err.reason, 'resolved path escapes sandbox root "/root"');
    });

    test('network() builds a disabled-network reason', () {
      final err = SandboxViolationError.network('host:80');
      expect(err.attempted, 'host:80');
      expect(err.reason, contains('network access is disabled'));
    });
  });
}
