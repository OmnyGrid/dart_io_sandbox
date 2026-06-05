/// Merges two Dart `package_config.json` files so a sandboxed test isolate can
/// resolve BOTH the project-under-test's packages and the packages the generated
/// bootstrap imports.
///
/// A `dart_io_sandbox test` run spawns each suite from a bootstrap that imports
/// `package:dart_io_sandbox` and `package:command_shield` *in addition to* the
/// project's own test file (which imports `package:test`). Those two sets of
/// packages live in two different `.dart_tool/package_config.json` files: the
/// project's own, and the CLI's. Spawning the isolate with only one of them
/// leaves the other unresolved — see the standalone-install reproduction. This
/// merge bridges the gap.
library;

import 'dart:convert';
import 'dart:io';

/// Writes a merged package config combining the [project]'s resolution with the
/// running CLI's [cli] resolution to [out], returning its URI.
///
/// The project wins on name collisions, so its packages (notably `test`,
/// `test_core` and the project's own libraries) are preserved verbatim; packages
/// present only in the CLI's config — `dart_io_sandbox`, `command_shield` and
/// any of their transitive deps the project does not itself declare — fill the
/// gaps. The CLI config already contains the full transitive closure of those
/// packages, so no dependency-graph walking is needed.
///
/// Every `rootUri` is rewritten to an absolute `file:` URI (resolved against its
/// source config file) so the merged file is independent of its own location.
Uri mergePackageConfigs({
  required Uri project,
  required Uri cli,
  required File out,
}) {
  // CLI first, then project, so project entries override on name collision.
  final byName = <String, Map<String, Object?>>{};
  for (final pkg in _packages(cli)) {
    byName[pkg['name'] as String] = _absolutize(pkg, cli);
  }
  for (final pkg in _packages(project)) {
    byName[pkg['name'] as String] = _absolutize(pkg, project);
  }

  final merged = <String, Object?>{
    'configVersion': 2,
    'generator': 'dart_io_sandbox',
    'packages': byName.values.toList(growable: false),
  };

  out
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(merged));
  return out.uri;
}

/// Reads and parses the `packages` array of the config file at [configUri].
Iterable<Map<String, Object?>> _packages(Uri configUri) {
  final json =
      jsonDecode(File.fromUri(configUri).readAsStringSync())
          as Map<String, Object?>;
  return (json['packages'] as List).cast<Map<String, Object?>>();
}

/// Returns a copy of [pkg] with its `rootUri` resolved to an absolute URI
/// against [configUri] (the location of the config the entry came from).
Map<String, Object?> _absolutize(Map<String, Object?> pkg, Uri configUri) {
  final rootUri = configUri.resolve(pkg['rootUri'] as String);
  return <String, Object?>{
    'name': pkg['name'],
    'rootUri': rootUri.toString(),
    if (pkg['packageUri'] != null) 'packageUri': pkg['packageUri'],
    if (pkg['languageVersion'] != null)
      'languageVersion': pkg['languageVersion'],
  };
}
