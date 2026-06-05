/// Generates the per-suite isolate bootstrap source.
///
/// The default VM platform's bootstrap calls
/// `internalBootstrapVmTest(() => test.main, sendPort)`, which sets up the test
/// engine *and runs every test body* inside the spawned isolate. To confine
/// those bodies we wrap that whole call in `Sandbox.run`, so the engine and all
/// of its scheduled callbacks inherit the sandbox zone. The sandbox policy is
/// emitted as Dart literals straight into the source — no cross-isolate
/// serialization is needed.
library;

import 'sandbox_test_config.dart';

/// Builds the bootstrap Dart source for the test library at [testUri] under
/// [config].
///
/// [languageVersionComment] is an optional `// @dart=` comment to prepend.
String generateBootstrap({
  required SandboxTestConfig config,
  required Uri testUri,
  String? languageVersionComment,
}) {
  final guard = config.commandGuard.enabled
      ? 'CommandGuard.forSyntax(CommandSyntax.${config.commandGuard.syntax.name}, '
            'denyOnReview: ${config.commandGuard.denyOnReview}, '
            'neverConfirmCritical: ${config.commandGuard.neverConfirmCritical})'
      : 'null';

  final onAccess = config.audit
      ? '''
      onAccess: (event) {
        stderr.writeln('[sandbox] '
            '\${event.allowed ? "ALLOW" : "DENY "} '
            '\${event.type.name} \${event.target}'
            '\${event.reason != null ? " :: \${event.reason}" : ""}');
      },'''
      : '';

  return '''
${languageVersionComment ?? ''}
import 'dart:io';
import 'dart:isolate';

import 'package:test_core/src/bootstrap/vm.dart';
import 'package:command_shield/command_shield.dart';
import 'package:dart_io_sandbox/dart_io_sandbox.dart';

import '$testUri' as test;

// This variable is read at runtime through the VM service and is unsafe to
// remove.
const packageConfigLocation = '';

void main(_, SendPort sendPort) {
  Sandbox.run(
    root: ${_dartString(config.root)},
    policy: ${_policyLiteral(config)},
    commandGuard: $guard,$onAccess
    action: () async {
      internalBootstrapVmTest(() => test.main, sendPort);
    },
  );
}
''';
}

String _policyLiteral(SandboxTestConfig c) =>
    'SandboxPolicy('
    'readOnly: ${c.readOnly}, '
    'allowProcess: ${c.allowProcess}, '
    'allowNetwork: ${c.allowNetwork}, '
    'allowedPaths: ${_stringListLiteral(c.allowedPaths)}, '
    'deniedPaths: ${_stringListLiteral(c.deniedPaths)}, '
    'allowedExecutables: ${_stringListLiteral(c.allowedExecutables)})';

String _stringListLiteral(List<String> items) =>
    '[${items.map(_dartString).join(', ')}]';

/// Encodes [s] as a single-quoted Dart string literal, escaping the characters
/// that are unsafe inside one. Used for filesystem paths, which may contain
/// backslashes (Windows) or quotes.
String _dartString(String s) {
  final buf = StringBuffer("'");
  for (final rune in s.runes) {
    switch (rune) {
      case 0x5C: // backslash
        buf.write(r'\\');
      case 0x27: // single quote
        buf.write(r"\'");
      case 0x24: // dollar
        buf.write(r'\$');
      case 0x0A: // newline
        buf.write(r'\n');
      case 0x0D: // carriage return
        buf.write(r'\r');
      default:
        buf.writeCharCode(rune);
    }
  }
  buf.write("'");
  return buf.toString();
}
