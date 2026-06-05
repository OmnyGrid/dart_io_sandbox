/// Resolves a [SandboxTestConfig] by layering preset < YAML file < CLI flags.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'presets.dart';
import 'sandbox_test_config.dart';

/// The sandbox-specific options parsed from the CLI. Every field is nullable so
/// that "not provided" is distinguishable from an explicit value and does not
/// clobber a preset/YAML setting.
class SandboxCliOverrides {
  final String? configPath;
  final String? preset;
  final String? root;
  final bool? readOnly;
  final bool? allowNetwork;
  final bool? allowProcess;
  final List<String> allowedExecutables;
  final List<String> allowedPaths;
  final List<String> deniedPaths;
  final bool? audit;

  const SandboxCliOverrides({
    this.configPath,
    this.preset,
    this.root,
    this.readOnly,
    this.allowNetwork,
    this.allowProcess,
    this.allowedExecutables = const [],
    this.allowedPaths = const [],
    this.deniedPaths = const [],
    this.audit,
  });
}

/// Resolves the effective configuration.
///
/// Precedence (lowest to highest): the named preset, the YAML config file (if
/// [SandboxCliOverrides.configPath] is set), then the CLI overrides. The jail
/// [root] is resolved to an absolute path against [cwd] so it is interpreted
/// identically in the spawned test isolates.
SandboxTestConfig resolveConfig(
  SandboxCliOverrides cli, {
  required String cwd,
}) {
  final yaml = _loadYaml(cli.configPath);

  final presetName =
      cli.preset ?? _stringOf(yaml, 'preset') ?? defaultPresetName;

  final rawRoot = cli.root ?? _stringOf(yaml, 'root') ?? '.';
  final root = p.normalize(
    p.isAbsolute(rawRoot) ? rawRoot : p.join(cwd, rawRoot),
  );

  var config = presetByName(presetName, root: root);

  // Layer 2: YAML file.
  config = config.copyWith(
    readOnly: _boolOf(yaml, 'read_only'),
    allowNetwork: _boolOf(yaml, 'allow_network'),
    allowProcess: _boolOf(yaml, 'allow_process'),
    allowedExecutables: _stringListOf(yaml, 'allowed_executables'),
    allowedPaths: _stringListOf(yaml, 'allowed_paths'),
    deniedPaths: _stringListOf(yaml, 'denied_paths'),
    audit: _boolOf(yaml, 'audit'),
    commandGuard: _commandGuardFromYaml(yaml, config.commandGuard),
  );

  // Layer 3: CLI flags (highest precedence). List flags are additive on top of
  // whatever the preset/YAML produced.
  config = config.copyWith(
    readOnly: cli.readOnly,
    allowNetwork: cli.allowNetwork,
    allowProcess: cli.allowProcess,
    allowedExecutables: cli.allowedExecutables.isEmpty
        ? null
        : [...config.allowedExecutables, ...cli.allowedExecutables],
    allowedPaths: cli.allowedPaths.isEmpty
        ? null
        : [...config.allowedPaths, ...cli.allowedPaths],
    deniedPaths: cli.deniedPaths.isEmpty
        ? null
        : [...config.deniedPaths, ...cli.deniedPaths],
    audit: cli.audit,
  );

  return config;
}

CommandGuardConfig? _commandGuardFromYaml(
  Map? yaml,
  CommandGuardConfig current,
) {
  final raw = yaml?['command_guard'];
  if (raw is! Map) return null;
  final syntaxName = _stringOf(raw, 'syntax');
  return current.copyWith(
    enabled: _boolOf(raw, 'enabled'),
    syntax: syntaxName == null
        ? null
        : CommandGuardConfig.parseSyntax(syntaxName),
    denyOnReview: _boolOf(raw, 'deny_on_review'),
    neverConfirmCritical: _boolOf(raw, 'never_confirm_critical'),
  );
}

Map? _loadYaml(String? configPath) {
  if (configPath == null) return null;
  final file = File(configPath);
  if (!file.existsSync()) {
    throw FormatException('config file not found: $configPath');
  }
  final doc = loadYaml(file.readAsStringSync(), sourceUrl: file.uri);
  if (doc == null) return null;
  if (doc is! Map) {
    throw FormatException('config file must be a YAML mapping: $configPath');
  }
  return doc;
}

String? _stringOf(Map? map, String key) {
  final v = map?[key];
  if (v == null) return null;
  if (v is String) return v;
  throw FormatException('config key "$key" must be a string, got: $v');
}

bool? _boolOf(Map? map, String key) {
  final v = map?[key];
  if (v == null) return null;
  if (v is bool) return v;
  throw FormatException('config key "$key" must be a boolean, got: $v');
}

List<String>? _stringListOf(Map? map, String key) {
  final v = map?[key];
  if (v == null) return null;
  if (v is List) return v.map((e) => e.toString()).toList(growable: false);
  throw FormatException('config key "$key" must be a list, got: $v');
}
