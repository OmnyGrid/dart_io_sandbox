// Fixture suite for the dart_io_sandbox CLI e2e tests. Not named `*_test.dart`
// so the package's own `dart test` run does not pick it up; it is executed only
// through `bin/dart_io_sandbox.dart` by `cli_test.dart`.
//
// Performs a real HTTPS request. HttpClient connects through Socket.connect, so
// the sandbox's network gate applies: this passes when the test isolate runs
// with network enabled (the default `safe` preset) and is blocked with a
// SandboxViolationError when network is disabled (`--no-allow-network`).
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('https GET to example.com', () async {
    final client = HttpClient();
    try {
      print('[network] fetching https://example.com/');
      final request = await client.getUrl(Uri.parse('https://example.com/'));
      final response = await request.close();
      final body = await response.transform(systemEncoding.decoder).join();

      print('[network] status code: ${response.statusCode}');
      print('[network] body length: ${body.length} chars');
      print(
        '[network] contains "Example Domain": '
        '${body.contains('Example Domain')}',
      );
      expect(response.statusCode, 200);
      expect(body, contains('Example Domain'));
      print('[network] passed');
    } finally {
      client.close(force: true);
    }
  });
}
