/// The resolved configuration for a `dart_io_sandbox test` run.
///
/// A [SandboxTestConfig] is the fully-populated result of layering, in
/// increasing precedence: a named preset (see `presets.dart`), an optional YAML
/// file, and CLI flag overrides. It describes the sandbox capabilities applied
/// to every test isolate; the test-selection arguments (paths, `-n`, `-t`, ...)
/// are forwarded to the underlying test runner separately.
library;

import 'package:command_shield/command_shield.dart';

/// Configuration of the optional semantic [CommandGuard] attached to each test
/// isolate's sandbox. Mirrors the literal-expressible subset of
/// `CommandGuard.forSyntax` (no `filter`/`confirm` closures, which cannot be
/// expressed in YAML).
class CommandGuardConfig {
  /// Whether a guard is attached at all. When false the executable allowlist is
  /// the only process gate.
  final bool enabled;

  /// The shell syntax `command_shield` parses commands as.
  final CommandSyntax syntax;

  /// Whether a `review` verdict is treated as a denial (fail-closed).
  final bool denyOnReview;

  /// Whether critical-severity denials can never be overridden.
  final bool neverConfirmCritical;

  const CommandGuardConfig({
    this.enabled = false,
    this.syntax = CommandSyntax.bash,
    this.denyOnReview = true,
    this.neverConfirmCritical = true,
  });

  CommandGuardConfig copyWith({
    bool? enabled,
    CommandSyntax? syntax,
    bool? denyOnReview,
    bool? neverConfirmCritical,
  }) => CommandGuardConfig(
    enabled: enabled ?? this.enabled,
    syntax: syntax ?? this.syntax,
    denyOnReview: denyOnReview ?? this.denyOnReview,
    neverConfirmCritical: neverConfirmCritical ?? this.neverConfirmCritical,
  );

  /// Parses a [CommandSyntax] from its name (case-insensitive). Accepts the
  /// common alias `posix` for [CommandSyntax.posixShell].
  static CommandSyntax parseSyntax(String name) {
    final n = name.trim().toLowerCase();
    return switch (n) {
      'generic' => CommandSyntax.generic,
      'posix' || 'posixshell' || 'posix_shell' => CommandSyntax.posixShell,
      'bash' => CommandSyntax.bash,
      'cmd' || 'windowscmd' || 'windows_cmd' => CommandSyntax.windowsCmd,
      'powershell' || 'pwsh' => CommandSyntax.powershell,
      _ => throw FormatException('unknown command-guard syntax: "$name"'),
    };
  }
}

/// The fully-resolved sandbox configuration applied to every test isolate.
class SandboxTestConfig {
  /// Filesystem jail root. All test `dart:io` access is confined here.
  final String root;

  /// When true, every write/delete/rename inside the root is denied.
  final bool readOnly;

  /// When true, socket creation (and transitively `HttpClient`) is permitted.
  final bool allowNetwork;

  /// When true, `Sandbox.process` execution is permitted (still subject to
  /// [allowedExecutables]).
  final bool allowProcess;

  /// Executables permitted by `Sandbox.process` (matched by exact string or
  /// basename).
  final List<String> allowedExecutables;

  /// Paths that may be accessed. Empty means "anything within [root]".
  final List<String> allowedPaths;

  /// Paths that may never be accessed (overrides [allowedPaths]).
  final List<String> deniedPaths;

  /// The optional semantic command guard.
  final CommandGuardConfig commandGuard;

  /// When true, every allow/deny access event is logged to stderr.
  final bool audit;

  const SandboxTestConfig({
    required this.root,
    this.readOnly = false,
    this.allowNetwork = false,
    this.allowProcess = false,
    this.allowedExecutables = const [],
    this.allowedPaths = const [],
    this.deniedPaths = const [],
    this.commandGuard = const CommandGuardConfig(),
    this.audit = false,
  });

  /// Returns a copy with the provided fields overridden. `null` arguments leave
  /// the existing value untouched, so this is the merge primitive used to layer
  /// YAML and CLI overrides on top of a preset.
  SandboxTestConfig copyWith({
    String? root,
    bool? readOnly,
    bool? allowNetwork,
    bool? allowProcess,
    List<String>? allowedExecutables,
    List<String>? allowedPaths,
    List<String>? deniedPaths,
    CommandGuardConfig? commandGuard,
    bool? audit,
  }) => SandboxTestConfig(
    root: root ?? this.root,
    readOnly: readOnly ?? this.readOnly,
    allowNetwork: allowNetwork ?? this.allowNetwork,
    allowProcess: allowProcess ?? this.allowProcess,
    allowedExecutables: allowedExecutables ?? this.allowedExecutables,
    allowedPaths: allowedPaths ?? this.allowedPaths,
    deniedPaths: deniedPaths ?? this.deniedPaths,
    commandGuard: commandGuard ?? this.commandGuard,
    audit: audit ?? this.audit,
  );
}
