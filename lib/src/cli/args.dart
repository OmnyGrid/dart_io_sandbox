/// CLI argument handling for the `dart_io_sandbox test` / `config` commands.
///
/// The command wraps the standard test runner: a handful of sandbox-specific
/// flags are consumed here and everything else is forwarded verbatim to the
/// runner (so the full `dart test` argument surface — paths, `-n`, `-t`, `-j`,
/// `-r`, ... — keeps working unchanged).
library;

import 'package:args/args.dart';

import 'config_loader.dart';

/// The result of parsing the raw `argv`: the sandbox overrides, the arguments
/// to forward to the test runner, and whether usage was requested.
class ParsedArgs {
  final SandboxCliOverrides sandbox;
  final List<String> testArgs;
  final bool help;

  const ParsedArgs({
    required this.sandbox,
    required this.testArgs,
    required this.help,
  });
}

/// Sandbox options that take a value (`--opt value` or `--opt=value`).
const Set<String> _valueOpts = {
  '--config',
  '--preset',
  '--root',
  '--allow-exe',
  '--allow-path',
  '--deny-path',
};

/// Sandbox negatable flag base names (accept `--name` and `--no-name`).
const Set<String> _flagBases = {
  'read-only',
  'allow-network',
  'allow-process',
  'audit',
};

final ArgParser _parser = _buildParser();

ArgParser _buildParser() {
  final parser = ArgParser(allowTrailingOptions: false);
  parser
    ..addOption('config', help: 'Path to a sandbox YAML config file.')
    ..addOption('preset', help: 'Named capability preset (default: safe).')
    ..addOption('root', help: 'Filesystem jail root (default: cwd).')
    ..addMultiOption(
      'allow-exe',
      help: 'Add an executable to the process allowlist. Repeatable.',
    )
    ..addMultiOption('allow-path', help: 'Add an allowed path. Repeatable.')
    ..addMultiOption('deny-path', help: 'Add a denied path. Repeatable.')
    ..addFlag('read-only', help: 'Deny all writes within the root.')
    ..addFlag('allow-network', help: 'Permit socket creation.')
    ..addFlag('allow-process', help: 'Permit Sandbox.process execution.')
    ..addFlag('audit', help: 'Log every allow/deny access event to stderr.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command usage.');
  return parser;
}

/// The indented help block listing the sandbox-specific options, reused by the
/// `test` and `config` command usage text.
String get sandboxOptionsUsage => _parser.usage;

/// Parses [argv] into sandbox overrides and forwarded test-runner arguments.
ParsedArgs parseArgs(List<String> argv) {
  final (sandboxTokens, testTokens, help) = _split(argv);
  final results = _parser.parse(sandboxTokens);

  bool? flag(String name) =>
      results.wasParsed(name) ? results[name] as bool : null;

  final sandbox = SandboxCliOverrides(
    configPath: results['config'] as String?,
    preset: results['preset'] as String?,
    root: results['root'] as String?,
    readOnly: flag('read-only'),
    allowNetwork: flag('allow-network'),
    allowProcess: flag('allow-process'),
    allowedExecutables: results['allow-exe'] as List<String>,
    allowedPaths: results['allow-path'] as List<String>,
    deniedPaths: results['deny-path'] as List<String>,
    audit: flag('audit'),
  );

  return ParsedArgs(
    sandbox: sandbox,
    testArgs: testTokens,
    help: help || (results['help'] as bool),
  );
}

/// Splits raw `argv` into sandbox tokens and forwarded test-runner tokens.
///
/// A token is a sandbox token when it is one of the [_valueOpts] (consuming its
/// value), a `--name`/`--no-name` form of a [_flagBases] entry, or `--help`/
/// `-h`. Everything else is forwarded untouched.
(List<String>, List<String>, bool) _split(List<String> argv) {
  final sandbox = <String>[];
  final test = <String>[];
  var help = false;

  for (var i = 0; i < argv.length; i++) {
    final token = argv[i];

    if (token == '--help' || token == '-h') {
      help = true;
      continue;
    }

    final eq = token.indexOf('=');
    final name = eq >= 0 ? token.substring(0, eq) : token;

    if (_valueOpts.contains(name)) {
      if (eq >= 0) {
        sandbox.add(token);
      } else {
        sandbox.add(token);
        if (i + 1 < argv.length) sandbox.add(argv[++i]);
      }
      continue;
    }

    if (_isFlagToken(token)) {
      sandbox.add(token);
      continue;
    }

    test.add(token);
  }

  return (sandbox, test, help);
}

bool _isFlagToken(String token) {
  for (final base in _flagBases) {
    if (token == '--$base' || token == '--no-$base') return true;
  }
  return false;
}
