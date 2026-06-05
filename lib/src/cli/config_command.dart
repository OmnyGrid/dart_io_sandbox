/// The `dart_io_sandbox config` command: resolves and prints the effective
/// sandbox configuration without running anything. Handy for verifying how a
/// preset, YAML file and CLI flags combine.
library;

import 'dart:io';

import 'args.dart';
import 'config_loader.dart';
import 'sandbox_test_config.dart';

/// Usage text for the `config` command.
String get configUsage => '''
Resolve and print the effective sandbox configuration (preset < YAML < flags)
without running any tests.

Usage: dart_io_sandbox config [sandbox options]

Sandbox options:
$sandboxOptionsUsage''';

/// Runs the `config` command with [args] (everything after `config`).
void runConfigCommand(List<String> args) {
  final ParsedArgs parsed;
  try {
    parsed = parseArgs(args);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln()
      ..writeln(configUsage);
    exitCode = 64;
    return;
  }

  if (parsed.help) {
    stdout.writeln(configUsage);
    return;
  }

  final SandboxTestConfig config;
  try {
    config = resolveConfig(parsed.sandbox, cwd: Directory.current.path);
  } on FormatException catch (e) {
    stderr.writeln('sandbox config error: ${e.message}');
    exitCode = 64;
    return;
  }

  stdout.write(_render(config));
}

String _render(SandboxTestConfig c) =>
    '''
root: ${c.root}
read_only: ${c.readOnly}
allow_network: ${c.allowNetwork}
allow_process: ${c.allowProcess}
allowed_executables: ${c.allowedExecutables}
allowed_paths: ${c.allowedPaths}
denied_paths: ${c.deniedPaths}
command_guard:
  enabled: ${c.commandGuard.enabled}
  syntax: ${c.commandGuard.syntax.name}
  deny_on_review: ${c.commandGuard.denyOnReview}
  never_confirm_critical: ${c.commandGuard.neverConfirmCritical}
audit: ${c.audit}
''';
