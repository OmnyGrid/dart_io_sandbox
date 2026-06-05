import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  group('SandboxAccessEvent.toString', () {
    test('an allowed event renders the ALLOW verdict and type', () {
      const event = SandboxAccessEvent(
        type: SandboxAccessType.read,
        target: '/root/a.txt',
        allowed: true,
      );
      expect(event.toString(), '[ALLOW] read /root/a.txt');
    });

    test('a denied event appends the reason', () {
      const event = SandboxAccessEvent(
        type: SandboxAccessType.write,
        target: '/root/b.txt',
        allowed: false,
        reason: 'policy is read-only',
      );
      expect(event.toString(), '[DENY] write /root/b.txt (policy is read-only)');
    });

    test('a two-path event renders the destination arrow', () {
      const event = SandboxAccessEvent(
        type: SandboxAccessType.rename,
        target: '/root/src.txt',
        allowed: true,
        destination: '/root/dst.txt',
      );
      expect(event.toString(), '[ALLOW] rename /root/src.txt -> /root/dst.txt');
    });

    test('a denied two-path event renders destination and reason', () {
      const event = SandboxAccessEvent(
        type: SandboxAccessType.rename,
        target: '/root/src.txt',
        allowed: false,
        destination: '../escape.txt',
        reason: 'escapes root',
      );
      expect(
        event.toString(),
        '[DENY] rename /root/src.txt -> ../escape.txt (escapes root)',
      );
    });
  });

  test('every access type has a stable name', () {
    expect(
      SandboxAccessType.values.map((t) => t.name).toSet(),
      {
        'read',
        'write',
        'delete',
        'rename',
        'list',
        'stat',
        'create',
        'process',
        'network',
      },
    );
  });
}
