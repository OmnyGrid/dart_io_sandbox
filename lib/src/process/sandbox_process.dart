/// Process execution layer: allowlisted, shell-free process spawning.
library;

import 'dart:convert';
import 'dart:io';

import '../context.dart';
import '../errors.dart';
import '../events.dart';
import '../sandbox.dart';

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

  /// Validates the request and returns the resolved working directory.
  String _authorize(
    SandboxContext ctx,
    String executable,
    List<String> arguments,
    String? workingDirectory,
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

    // A working directory, if given, must resolve inside the sandbox root.
    final cwd = workingDirectory != null
        ? ctx.resolve(workingDirectory)
        : ctx.cwd;

    ctx.emit(
      SandboxAccessEvent(
        type: SandboxAccessType.process,
        target: executable,
        allowed: true,
      ),
    );
    return cwd;
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
    final cwd = _authorize(ctx, executable, arguments, workingDirectory);
    return Process.run(
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
    final cwd = _authorize(ctx, executable, arguments, workingDirectory);
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
    final cwd = _authorize(ctx, executable, arguments, workingDirectory);
    return Process.start(
      executable,
      arguments,
      workingDirectory: cwd,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: false,
      mode: mode,
    );
  }
}
