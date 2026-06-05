/// The `dart_io_sandbox test` command: runs a Dart test suite like `dart test`,
/// but with every test isolate confined to a `Sandbox.run` jail.
library;

// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:test_api/backend.dart' show Runtime;
import 'package:test_core/src/executable.dart' as executable;
import 'package:test_core/src/runner/hack_register_platform.dart';

import 'args.dart';
import 'config_loader.dart';
import 'sandbox_test_config.dart';
import 'sandbox_vm_platform.dart';

/// Usage text for the `test` command.
String get testUsage =>
    '''
Run a Dart test suite with every test isolate confined to a Sandbox.run jail.

Usage: dart_io_sandbox test [sandbox options] [test runner arguments...]

Sandbox options:
$sandboxOptionsUsage

All other arguments (paths, -n/--name, -t/--tags, -j/--concurrency,
-r/--reporter, ...) are forwarded to the test runner unchanged.''';

/// Runs the `test` command with [args] (everything after `test`).
///
/// Sets the global [exitCode] exactly like `dart test` (0 pass / 1 fail / >1
/// error / 64 usage).
Future<void> runTestCommand(List<String> args) async {
  final ParsedArgs parsed;
  try {
    parsed = parseArgs(args);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln()
      ..writeln(testUsage);
    exitCode = 64; // usage
    return;
  }

  if (parsed.help) {
    stdout.writeln(testUsage);
    return;
  }

  final SandboxTestConfig config;
  try {
    config = resolveConfig(parsed.sandbox, cwd: Directory.current.path);
  } on FormatException catch (e) {
    stderr.writeln('sandbox config error: ${e.message}');
    exitCode = 64; // usage
    return;
  }

  // Override the default VM platform with one that jails every test isolate.
  // The loader applies globally-registered plugins last, so this wins.
  registerPlatformPlugin([Runtime.vm], () => SandboxVMPlatform(config));

  // Hand the remaining arguments to the standard runner; it sets the global
  // exitCode (0 pass / 1 fail / >1 error) exactly like `dart test`.
  await executable.main(parsed.testArgs);
}
