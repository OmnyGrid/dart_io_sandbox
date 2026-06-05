/// Built-in capability presets for the `dart_io_sandbox` CLI.
///
/// A preset is the base layer of configuration; a YAML file and CLI flags are
/// layered on top (see `config_loader.dart`). [defaultPresetName] is used when
/// neither the config file nor the CLI selects one.
library;

import 'package:command_shield/command_shield.dart';

import 'sandbox_test_config.dart';

/// The preset selected when none is specified.
const String defaultPresetName = 'safe';

/// Returns the preset named [name], rooted at [root].
///
/// Throws a [FormatException] if [name] is not a known preset.
SandboxTestConfig presetByName(String name, {required String root}) {
  final builder = _presets[name];
  if (builder == null) {
    throw FormatException(
      'unknown preset "$name"; available: ${availablePresets.join(', ')}',
    );
  }
  return builder(root);
}

/// The names of all built-in presets.
List<String> get availablePresets => _presets.keys.toList(growable: false);

typedef _PresetBuilder = SandboxTestConfig Function(String root);

final Map<String, _PresetBuilder> _presets = {
  'safe': _safe,
  'paranoid': _paranoid,
};

/// The default, practical preset for everyday Dart test suites.
///
/// Read-write within the jail root (temp files, `.dart_tool`, fixtures),
/// network allowed (many suites and `pub`/`dart` need it), and process
/// execution allowed but restricted to the Dart toolchain — with a bash
/// [CommandGuard] so even an allowlisted `dart`/`flutter`/`pub` cannot be
/// invoked destructively.
SandboxTestConfig _safe(String root) => SandboxTestConfig(
  root: root,
  readOnly: false,
  allowNetwork: true,
  allowProcess: true,
  allowedExecutables: const ['dart', 'flutter', 'pub'],
  commandGuard: const CommandGuardConfig(
    enabled: true,
    syntax: CommandSyntax.bash,
    denyOnReview: true,
    neverConfirmCritical: true,
  ),
);

/// A maximally restrictive preset for untrusted suites: read-only filesystem,
/// no network, no process execution.
SandboxTestConfig _paranoid(String root) => SandboxTestConfig(
  root: root,
  readOnly: true,
  allowNetwork: false,
  allowProcess: false,
);
