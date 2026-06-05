/// Process execution layer: allowlisted, shell-free process spawning.
library;

import 'dart:convert';
import 'dart:io';

import '../context.dart';
import '../errors.dart';
import '../events.dart';
import '../sandbox.dart';
import 'command_guard.dart';

/// Runs external processes under sandbox policy control.
///
/// Obtain the singleton via [Sandbox.process]. Every call requires an active
/// [Sandbox.run], an enabled `allowProcess` policy, and an executable present
/// in the policy's `allowedExecutables` allowlist. Processes are never run
/// through a shell, and arguments containing shell-control characters are
/// rejected.
class SandboxProcessManager {
  /// Characters that are meaningful to a shell. We never use a shell, but we
  /// still reject them defensively so a policy change to a shell-based runner
  /// can't silently become injectable.
  static const List<String> _shellMeta = [
    ';',
    '&',
    '|',
    r'$',
    '`',
    '<',
    '>',
    '\n',
    '\r',
    '\x00',
  ];

  SandboxContext _requireContext() {
    final ctx = currentSandboxContext;
    if (ctx == null) {
      throw SandboxProcessDeniedError(
        '<process>',
        'the process API can only be used inside Sandbox.run',
      );
    }
    return ctx;
  }

  void _validatePattern(SandboxContext ctx, String value) {
    for (final meta in _shellMeta) {
      if (value.contains(meta)) {
        ctx.emit(
          SandboxAccessEvent(
            type: SandboxAccessType.process,
            target: value,
            allowed: false,
            reason: 'contains a blocked shell character',
          ),
        );
        throw SandboxProcessDeniedError(
          value,
          'argument contains a blocked shell character',
        );
      }
    }
  }

  /// The synchronous, guard-independent checks: process enablement,
  /// shell-metacharacter rejection and the executable allowlist. Throws (and
  /// emits a denial event) on failure. Kept synchronous so it surfaces errors
  /// the same way regardless of whether a [CommandGuard] is attached.
  void _preCheck(
    SandboxContext ctx,
    String executable,
    List<String> arguments,
  ) {
    if (!ctx.policy.allowProcess) {
      ctx.emit(
        SandboxAccessEvent(
          type: SandboxAccessType.process,
          target: executable,
          allowed: false,
          reason: 'process execution is disabled by the sandbox policy',
        ),
      );
      throw SandboxProcessDeniedError(
        executable,
        'process execution is disabled by the sandbox policy',
      );
    }

    _validatePattern(ctx, executable);
    for (final arg in arguments) {
      _validatePattern(ctx, arg);
    }

    if (!ctx.policy.allowsExecutable(executable)) {
      ctx.emit(
        SandboxAccessEvent(
          type: SandboxAccessType.process,
          target: executable,
          allowed: false,
          reason: 'executable is not on the allowlist',
        ),
      );
      throw SandboxProcessDeniedError(
        executable,
        'executable is not on the allowlist',
      );
    }
  }

  /// Applies a [CommandGuard] outcome: emits a denial event and throws when the
  /// command is denied, otherwise returns an optional audit note (set when a
  /// confirmation callback overrode a denial).
  String? _applyOutcome(
    SandboxContext ctx,
    String executable,
    CommandGuardOutcome outcome,
  ) {
    if (!outcome.allowed) {
      ctx.emit(
        SandboxAccessEvent(
          type: SandboxAccessType.process,
          target: executable,
          allowed: false,
          reason: outcome.reason,
        ),
      );
      throw SandboxProcessDeniedError(executable, outcome.reason!);
    }
    return outcome.overridden ? outcome.reason : null;
  }

  /// Resolves the working directory and emits the success event. [note] carries
  /// an optional audit annotation (e.g. a confirmation override). Returns the
  /// resolved working directory.
  String _finish(
    SandboxContext ctx,
    String executable,
    String? workingDirectory,
    String? note,
  ) {
    // A working directory, if given, must resolve inside the sandbox root.
    final cwd = workingDirectory != null
        ? ctx.resolve(workingDirectory)
        : ctx.cwd;

    ctx.emit(
      SandboxAccessEvent(
        type: SandboxAccessType.process,
        target: executable,
        allowed: true,
        reason: note,
      ),
    );
    return cwd;
  }

  /// Asynchronous guard step used by [run] and [start], run after the
  /// synchronous [_preCheck]. Awaits the optional command guard and returns the
  /// resolved working directory.
  Future<String> _authorize(
    SandboxContext ctx,
    String executable,
    List<String> arguments,
    String? workingDirectory,
  ) async {
    String? note;
    final guard = ctx.commandGuard;
    if (guard != null) {
      note = _applyOutcome(
        ctx,
        executable,
        await guard.evaluate(executable, arguments),
      );
    }
    return _finish(ctx, executable, workingDirectory, note);
  }

  /// Synchronous guard step used by [runSync], run after [_preCheck]. A
  /// [CommandGuard] with asynchronous callbacks throws [UnsupportedError] here.
  String _authorizeSync(
    SandboxContext ctx,
    String executable,
    List<String> arguments,
    String? workingDirectory,
  ) {
    String? note;
    final guard = ctx.commandGuard;
    if (guard != null) {
      note = _applyOutcome(
        ctx,
        executable,
        guard.evaluateSync(executable, arguments),
      );
    }
    return _finish(ctx, executable, workingDirectory, note);
  }

  /// Runs [executable] with [arguments] and returns its result. Never uses a
  /// shell.
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    final ctx = _requireContext();
    _preCheck(ctx, executable, arguments);
    return _authorize(ctx, executable, arguments, workingDirectory).then(
      (cwd) => Process.run(
        executable,
        arguments,
        workingDirectory: cwd,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
        runInShell: false,
        stdoutEncoding: stdoutEncoding,
        stderrEncoding: stderrEncoding,
      ),
    );
  }

  /// Synchronous variant of [run].
  ProcessResult runSync(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    final ctx = _requireContext();
    _preCheck(ctx, executable, arguments);
    final cwd = _authorizeSync(ctx, executable, arguments, workingDirectory);
    return Process.runSync(
      executable,
      arguments,
      workingDirectory: cwd,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: false,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }

  /// Starts a long-running process. Never uses a shell.
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    final ctx = _requireContext();
    _preCheck(ctx, executable, arguments);
    return _authorize(ctx, executable, arguments, workingDirectory).then(
      (cwd) => Process.start(
        executable,
        arguments,
        workingDirectory: cwd,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
        runInShell: false,
        mode: mode,
      ),
    );
  }
}
