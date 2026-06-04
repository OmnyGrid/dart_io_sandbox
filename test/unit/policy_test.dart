import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  group('read-only mode', () {
    const policy = SandboxPolicy(readOnly: true);

    test('allows reads', () {
      expect(policy.denyReason(AccessMode.read, '/r/a'), isNull);
    });

    test('blocks writes', () {
      expect(policy.denyReason(AccessMode.write, '/r/a'), isNotNull);
    });

    test('blocks deletes', () {
      expect(policy.denyReason(AccessMode.delete, '/r/a'), isNotNull);
    });

    test('blocks renames', () {
      expect(policy.denyReason(AccessMode.rename, '/r/a'), isNotNull);
    });

    test('check() throws on write', () {
      expect(
        () => policy.check(AccessMode.write, '/r/a'),
        throwsA(isA<SandboxPolicyError>()),
      );
    });
  });

  group('allow list', () {
    const policy = SandboxPolicy(allowedPaths: ['/r/safe']);

    test('allows a path inside an allowed entry', () {
      expect(policy.denyReason(AccessMode.read, '/r/safe/file'), isNull);
    });

    test('allows the allowed entry itself', () {
      expect(policy.denyReason(AccessMode.read, '/r/safe'), isNull);
    });

    test('denies a path outside the allow list', () {
      expect(policy.denyReason(AccessMode.read, '/r/other'), isNotNull);
    });

    test('empty allow list allows everything', () {
      const open = SandboxPolicy();
      expect(open.denyReason(AccessMode.read, '/r/anything'), isNull);
    });
  });

  group('deny overrides allow', () {
    const policy = SandboxPolicy(
      allowedPaths: ['/r/safe'],
      deniedPaths: ['/r/safe/secret'],
    );

    test('allows non-denied path within allow list', () {
      expect(policy.denyReason(AccessMode.read, '/r/safe/ok'), isNull);
    });

    test('denies path that is both allowed and denied', () {
      final reason = policy.denyReason(AccessMode.read, '/r/safe/secret/k');
      expect(reason, contains('deny list'));
    });
  });

  group('executable allowlist', () {
    test('empty list denies all executables (fail-closed)', () {
      const policy = SandboxPolicy(allowProcess: true);
      expect(policy.allowsExecutable('echo'), isFalse);
    });

    test('matches by exact name', () {
      const policy = SandboxPolicy(allowedExecutables: ['echo']);
      expect(policy.allowsExecutable('echo'), isTrue);
    });

    test('matches by basename', () {
      const policy = SandboxPolicy(allowedExecutables: ['echo']);
      expect(policy.allowsExecutable('/bin/echo'), isTrue);
    });

    test('rejects a non-listed executable', () {
      const policy = SandboxPolicy(allowedExecutables: ['echo']);
      expect(policy.allowsExecutable('rm'), isFalse);
    });
  });

  group('intersect (nesting)', () {
    test('read-only is OR-ed', () {
      const child = SandboxPolicy();
      const parent = SandboxPolicy(readOnly: true);
      expect(child.intersect(parent).readOnly, isTrue);
    });

    test('allowProcess is AND-ed', () {
      const child = SandboxPolicy(allowProcess: true);
      const parent = SandboxPolicy(allowProcess: false);
      expect(child.intersect(parent).allowProcess, isFalse);
    });

    test('deny lists are unioned', () {
      const child = SandboxPolicy(deniedPaths: ['/a']);
      const parent = SandboxPolicy(deniedPaths: ['/b']);
      expect(child.intersect(parent).deniedPaths, containsAll(['/a', '/b']));
    });

    test('executables are intersected', () {
      const child = SandboxPolicy(allowedExecutables: ['echo', 'ls']);
      const parent = SandboxPolicy(allowedExecutables: ['echo']);
      expect(child.intersect(parent).allowedExecutables, ['echo']);
    });
  });
}
