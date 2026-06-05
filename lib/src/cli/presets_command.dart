/// The `dart_io_sandbox presets` command: lists the built-in capability
/// presets and the policy each one applies.
library;

import 'dart:io';

import 'presets.dart';

/// Usage text for the `presets` command.
String get presetsUsage => '''
List the built-in capability presets and the policy each applies.

Usage: dart_io_sandbox presets''';

/// Runs the `presets` command with [args] (everything after `presets`).
void runPresetsCommand(List<String> args) {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(presetsUsage);
    return;
  }

  final buf = StringBuffer();
  for (final name in availablePresets) {
    final c = presetByName(name, root: '<root>');
    final guard = c.commandGuard.enabled
        ? '${c.commandGuard.syntax.name} (on)'
        : 'off';
    buf
      ..writeln('$name${name == defaultPresetName ? '  (default)' : ''}:')
      ..writeln('  read_only:           ${c.readOnly}')
      ..writeln('  allow_network:       ${c.allowNetwork}')
      ..writeln('  allow_process:       ${c.allowProcess}')
      ..writeln('  allowed_executables: ${c.allowedExecutables}')
      ..writeln('  command_guard:       $guard')
      ..writeln();
  }
  stdout.write(buf);
}
