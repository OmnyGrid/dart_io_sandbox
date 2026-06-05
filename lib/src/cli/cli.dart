/// Top-level command dispatch for the `dart_io_sandbox` CLI.
///
/// A small hand-rolled dispatcher (rather than `package:args`'
/// `CommandRunner`) so the `test` command can forward the full, open-ended
/// `dart test` argument surface verbatim — see `args.dart` for how sandbox
/// flags are split from forwarded runner arguments.
library;

import 'dart:io';

import 'config_command.dart';
import 'presets_command.dart';
import 'test_command.dart';

/// Top-level usage text.
String get topUsage => '''
dart_io_sandbox — run Dart code confined to a dart_io_sandbox Sandbox.run jail.

Usage: dart_io_sandbox <command> [arguments]

Available commands:
  test      Run a test suite with every test isolate sandboxed (like `dart test`).
  config    Print the resolved sandbox configuration (preset < YAML < flags).
  presets   List the built-in capability presets.
  help      Show usage for dart_io_sandbox or a specific command.

Run "dart_io_sandbox help <command>" for usage of a specific command.''';

/// Dispatches [argv] to a command. Commands set the global [exitCode]; this
/// returns when dispatch is complete.
Future<void> runCli(List<String> argv) async {
  if (argv.isEmpty) {
    stdout.writeln(topUsage);
    return;
  }

  final command = argv.first;
  final rest = argv.sublist(1);

  switch (command) {
    case 'test':
      await runTestCommand(rest);
    case 'config':
      runConfigCommand(rest);
    case 'presets':
      runPresetsCommand(rest);
    case 'help':
      _help(rest);
    case '-h' || '--help':
      stdout.writeln(topUsage);
    default:
      stderr
        ..writeln('Could not find a command named "$command".')
        ..writeln()
        ..writeln(topUsage);
      exitCode = 64; // usage
  }
}

void _help(List<String> rest) {
  if (rest.isEmpty) {
    stdout.writeln(topUsage);
    return;
  }
  switch (rest.first) {
    case 'test':
      stdout.writeln(testUsage);
    case 'config':
      stdout.writeln(configUsage);
    case 'presets':
      stdout.writeln(presetsUsage);
    default:
      stderr
        ..writeln('Could not find a command named "${rest.first}".')
        ..writeln()
        ..writeln(topUsage);
      exitCode = 64;
  }
}
