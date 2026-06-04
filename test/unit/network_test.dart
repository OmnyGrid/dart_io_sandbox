import 'dart:io';

import 'package:dart_io_sandbox/dart_io_sandbox.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;
  late String root;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('sbx_net');
    root = tempRoot.path;
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  group('network gate (allowNetwork: false)', () {
    test('Socket.connect is blocked', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          expect(
            () => Socket.connect('127.0.0.1', 9),
            throwsA(isA<SandboxViolationError>()),
          );
        },
      );
    });

    test('Socket.startConnect is blocked', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          expect(
            () => Socket.startConnect('127.0.0.1', 9),
            throwsA(isA<SandboxViolationError>()),
          );
        },
      );
    });

    test('ServerSocket.bind is blocked', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          expect(
            () => ServerSocket.bind('127.0.0.1', 0),
            throwsA(isA<SandboxViolationError>()),
          );
        },
      );
    });

    test(
      'HttpClient is blocked transitively (routes through socketConnect)',
      () async {
        await Sandbox.run(
          root: root,
          action: () async {
            final client = HttpClient();
            addTearDown(() => client.close(force: true));
            await expectLater(() async {
              final req = await client.getUrl(Uri.parse('http://127.0.0.1:9/'));
              await req.close();
            }(), throwsA(isA<SandboxViolationError>()));
          },
        );
      },
    );

    test('a denied network access emits a deny event', () async {
      final events = <SandboxAccessEvent>[];
      await Sandbox.run(
        root: root,
        onAccess: events.add,
        action: () async {
          try {
            await Socket.connect('127.0.0.1', 9);
          } on SandboxViolationError {
            // expected — we only care that a deny event was emitted.
          }
        },
      );
      expect(
        events.any((e) => e.type == SandboxAccessType.network && !e.allowed),
        isTrue,
      );
    });
  });

  group('network gate (allowNetwork: true)', () {
    test('a loopback ServerSocket bind succeeds', () async {
      await Sandbox.run(
        root: root,
        policy: const SandboxPolicy(allowNetwork: true),
        action: () async {
          final server = await ServerSocket.bind('127.0.0.1', 0);
          expect(server.port, greaterThan(0));
          await server.close();
        },
      );
    });

    test('a loopback bind emits an allow event', () async {
      final events = <SandboxAccessEvent>[];
      await Sandbox.run(
        root: root,
        policy: const SandboxPolicy(allowNetwork: true),
        onAccess: events.add,
        action: () async {
          final server = await ServerSocket.bind('127.0.0.1', 0);
          await server.close();
        },
      );
      expect(
        events.any((e) => e.type == SandboxAccessType.network && e.allowed),
        isTrue,
      );
    });
  });

  // KNOWN LIMITATION: dart:io's IOOverrides exposes hooks only for
  // Socket.connect / Socket.startConnect / ServerSocket.bind. RawSocket,
  // RawServerSocket and RawDatagramSocket (UDP) have no override hook, so the
  // sandbox cannot intercept them. These tests pin that behavior so any future
  // SDK change (or regression) is noticed. See README "Limitations".
  group('raw sockets / UDP are NOT interceptable (documented gap)', () {
    test(
      'RawServerSocket.bind escapes the gate even when network is denied',
      () async {
        await Sandbox.run(
          root: root,
          action: () async {
            // No SandboxViolationError: this is the known cooperative-confinement
            // gap, not a feature.
            final server = await RawServerSocket.bind('127.0.0.1', 0);
            expect(server.port, greaterThan(0));
            await server.close();
          },
        );
      },
    );

    test('RawDatagramSocket.bind (UDP) escapes the gate even when network '
        'is denied', () async {
      await Sandbox.run(
        root: root,
        action: () async {
          final socket = await RawDatagramSocket.bind('127.0.0.1', 0);
          expect(socket.port, greaterThan(0));
          socket.close();
        },
      );
    });
  });
}
