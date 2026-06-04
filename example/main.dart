// Demonstrates the core features of dart_io_sandbox:
//   * confined filesystem access via Sandbox.run + plain dart:io APIs,
//   * allow/deny policy enforcement,
//   * allowlisted process execution,
//   * an access hook for auditing,
//   * path-traversal being blocked.
import 'dart:io';

import 'package:dart_io_sandbox/dart_io_sandbox.dart';

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('sandbox_example').path;

  await Sandbox.run(
    root: root,
    policy: SandboxPolicy(
      readOnly: false,
      allowProcess: true,
      allowedPaths: [root], // everything under the root
      deniedPaths: ['$root/secret'],
      allowedExecutables: ['echo'],
    ),
    onAccess: (event) => print('audit: $event'),
    action: () async {
      // Plain dart:io — transparently sandboxed.
      final file = File('data.txt');
      await file.writeAsString('hello');
      print('read back: ${await file.readAsString()}');

      // Allowlisted process execution.
      final result = await Sandbox.process.run('echo', ['sandboxed']);
      print('echo exit=${result.exitCode} stdout=${result.stdout.trim()}');

      // Denied by the deny list.
      try {
        await File('secret/keys.txt').writeAsString('nope');
      } on SandboxPolicyError catch (e) {
        print('blocked by policy: ${e.reason}');
      }

      // Blocked by path-traversal protection.
      try {
        File('../../etc/passwd');
      } on SandboxViolationError catch (e) {
        print('blocked traversal: ${e.reason}');
      }
    },
  );

  Directory(root).deleteSync(recursive: true);
}
