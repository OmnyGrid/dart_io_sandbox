/// `dart_io_sandbox` — a command-line tool for running Dart code confined to a
/// dart_io_sandbox `Sandbox.run` jail.
///
/// Commands:
///   test      Run a test suite with every test isolate sandboxed (like
///             `dart test`).
///   config    Print the resolved sandbox configuration.
///   presets   List the built-in capability presets.
///   help      Show usage.
library;

import 'package:dart_io_sandbox/src/cli/cli.dart';

Future<void> main(List<String> argv) => runCli(argv);
