/// Optional semantic command-analysis layer for [Sandbox.process], backed by
/// `package:command_shield`.
library;

import 'dart:async';

import 'package:command_shield/command_shield.dart';

/// The analysed command handed to a [CommandFilter] or [CommandConfirm].
///
/// Bundles the raw request ([executable], [arguments]), the reconstructed
/// [command] string that was analysed, and the full `command_shield`
/// [result] (decision, findings and severity) so callbacks can make an
/// informed decision.
class CommandReview {
  /// The executable that was requested.
  final String executable;

  /// The arguments that were requested.
  final List<String> arguments;

  /// The command string that was analysed (`executable` joined with
  /// `arguments`). Shell metacharacters are already rejected by the sandbox, so
  /// this reconstruction is unambiguous.
  final String command;

  /// The full `command_shield` analysis of [command].
  final CommandResult result;

  const CommandReview({
    required this.executable,
    required this.arguments,
    required this.command,
    required this.result,
  });

  /// `command_shield`'s verdict for [command].
  CommandDecision get decision => result.decision;

  /// A human-readable explanation built from the analysis findings.
  String get explanation => result.findings.isEmpty
      ? result.decision.name
      : result.findings.map((f) => f.message).join('; ');
}

/// The result of evaluating a command against a [CommandGuard].
class CommandGuardOutcome {
  /// Whether the command may proceed.
  final bool allowed;

  /// Whether the command is allowed only because a [CommandConfirm] callback
  /// overrode a denial. Used to flag the audit event.
  final bool overridden;

  /// The denial reason (when [allowed] is false) or the override note (when
  /// [overridden] is true). `null` for a plain allow.
  final String? reason;

  /// The command is permitted with no caveats.
  const CommandGuardOutcome.allowed()
    : allowed = true,
      overridden = false,
      reason = null;

  /// The command was denied but a [CommandConfirm] callback overrode it.
  const CommandGuardOutcome.confirmed(this.reason)
    : allowed = true,
      overridden = true;

  /// The command is denied.
  const CommandGuardOutcome.denied(this.reason)
    : allowed = false,
      overridden = false;
}

/// A pluggable filter invoked for **every** command, with the analysis already
/// computed ([CommandReview]). Return a [CommandDecision] to override
/// `command_shield`'s verdict (force allow / review / deny), or `null` to keep
/// it. May be synchronous or asynchronous.
typedef CommandFilter =
    FutureOr<CommandDecision?> Function(CommandReview review);

/// A confirmation callback invoked when a command would otherwise be **denied**.
/// Return `true` to override the denial and let the command run, `false` to keep
/// it denied. May be synchronous or asynchronous.
typedef CommandConfirm = FutureOr<bool> Function(CommandReview review);

/// An opt-in second gate for process execution that runs each command through
/// `package:command_shield`'s deterministic, execution-free analysis.
///
/// The sandbox's built-in process checks answer *"is this executable allowed?"*
/// ([SandboxPolicy.allowedExecutables]) but not *"is this specific command
/// dangerous?"*. A [CommandGuard] adds flag/argument-level analysis on top: an
/// allowlisted `bash`/`git`/`rm` invoked with destructive or
/// privilege-escalating arguments can still be denied.
///
/// Two optional callbacks extend the analysis:
///  * [filter] runs for *every* command and can override the verdict
///    (force allow / review / deny) using the full [CommandReview].
///  * [confirm] runs whenever a command would be *denied* and can override the
///    denial (e.g. an interactive "run anyway?" prompt).
///
/// The feature is **off by default**. Attach a guard to a sandbox via
/// `Sandbox.run(commandGuard: ...)` or [SandboxConfig.commandGuard]; when none
/// is attached, process execution behaves exactly as before (allowlist only).
///
/// A `command_shield` `review` verdict is treated as **deny** by default
/// ([denyOnReview]), keeping the layer fail-closed; set `denyOnReview: false`
/// to permit (but still audit) commands that only warrant review.
///
/// By default ([neverConfirmCritical]) critical-severity denials cannot be
/// overridden by [confirm] — the worst commands are always blocked.
///
/// > **Async & `runSync`:** [filter] and [confirm] may be asynchronous. They
/// > are awaited by [Sandbox.process] `run` and `start`. The synchronous
/// > [Sandbox.process] `runSync` cannot await: if a callback returns a `Future`
/// > it throws an [UnsupportedError] — use the async `run` instead.
///
/// > **Nesting:** command analysis is *not* composed across nested sandboxes.
/// > The innermost non-null [CommandGuard] wins (the same inheritance model the
/// > sandbox uses for its `onAccess` hook). A nested sandbox that sets its own
/// > guard replaces — rather than layers on top of — the parent's.
class CommandGuard {
  /// The underlying `command_shield` analyzer used to validate commands.
  final CommandShield shield;

  /// Whether a `command_shield` `review` verdict should be treated as a denial.
  ///
  /// Defaults to `true` (fail-closed). When `false`, reviewed commands are
  /// permitted but still surfaced through the sandbox's `onAccess` audit hook.
  final bool denyOnReview;

  /// Optional per-command filter that can override the analysis verdict.
  final CommandFilter? filter;

  /// Optional confirmation callback consulted before a command is denied.
  final CommandConfirm? confirm;

  /// Whether commands `command_shield` classifies as **critical-severity
  /// denials** may never be overridden by [confirm].
  ///
  /// Defaults to `true` (the safety floor is on). When `true`, a command whose
  /// analysis is both [CommandDecision.deny] and [SecurityLevel.critical] (e.g.
  /// `rm -rf /`) is denied outright: the [confirm] callback is not even
  /// consulted for it. Set to `false` to allow [confirm] to override even
  /// critical denials.
  ///
  /// The check is based on `command_shield`'s classification of the command,
  /// not on any verdict a [filter] forced, and only affects the [confirm] step.
  final bool neverConfirmCritical;

  /// Creates a guard wrapping an existing [shield].
  const CommandGuard(
    this.shield, {
    this.denyOnReview = true,
    this.filter,
    this.confirm,
    this.neverConfirmCritical = true,
  });

  /// Creates a guard using `command_shield`'s default policy for [syntax].
  ///
  /// Since the sandbox never runs commands through a shell, [CommandSyntax.bash]
  /// (or [CommandSyntax.generic]) is usually appropriate.
  factory CommandGuard.forSyntax(
    CommandSyntax syntax, {
    bool denyOnReview = true,
    CommandFilter? filter,
    CommandConfirm? confirm,
    bool neverConfirmCritical = true,
  }) => CommandGuard(
    CommandShield(defaultSyntax: syntax),
    denyOnReview: denyOnReview,
    filter: filter,
    confirm: confirm,
    neverConfirmCritical: neverConfirmCritical,
  );

  /// Analyses [executable] with [arguments], applying the [filter] and (on a
  /// denial) the [confirm] callback. Awaits asynchronous callbacks.
  Future<CommandGuardOutcome> evaluate(
    String executable,
    List<String> arguments,
  ) async {
    final review = _review(executable, arguments);
    var decision = review.decision;
    var fromFilter = false;
    if (filter != null) {
      final override = await filter!(review);
      if (override != null && override != decision) {
        decision = override;
        fromFilter = true;
      }
    }
    if (!_isDenied(decision)) return const CommandGuardOutcome.allowed();
    final criticalBlocked = neverConfirmCritical && _criticalDeny(review);
    if (confirm != null && !criticalBlocked && await confirm!(review)) {
      return CommandGuardOutcome.confirmed(_overrideNote(review));
    }
    return CommandGuardOutcome.denied(
      _denialReason(decision, review, fromFilter, criticalBlocked),
    );
  }

  /// Synchronous variant of [evaluate] used by [Sandbox.process] `runSync`.
  ///
  /// Throws [UnsupportedError] if [filter] or [confirm] returns a `Future`,
  /// since a synchronous run cannot await it.
  CommandGuardOutcome evaluateSync(String executable, List<String> arguments) {
    final review = _review(executable, arguments);
    var decision = review.decision;
    var fromFilter = false;
    if (filter != null) {
      final override = filter!(review);
      if (override is Future) {
        throw UnsupportedError(
          'an async CommandGuard.filter is not supported with '
          'Sandbox.process.runSync; use run() instead',
        );
      }
      if (override != null && override != decision) {
        decision = override;
        fromFilter = true;
      }
    }
    if (!_isDenied(decision)) return const CommandGuardOutcome.allowed();
    final criticalBlocked = neverConfirmCritical && _criticalDeny(review);
    if (confirm != null && !criticalBlocked) {
      final confirmed = confirm!(review);
      if (confirmed is Future) {
        throw UnsupportedError(
          'an async CommandGuard.confirm is not supported with '
          'Sandbox.process.runSync; use run() instead',
        );
      }
      if (confirmed) {
        return CommandGuardOutcome.confirmed(_overrideNote(review));
      }
    }
    return CommandGuardOutcome.denied(
      _denialReason(decision, review, fromFilter, criticalBlocked),
    );
  }

  CommandReview _review(String executable, List<String> arguments) {
    final command = [executable, ...arguments].join(' ');
    return CommandReview(
      executable: executable,
      arguments: arguments,
      command: command,
      result: shield.validate(command),
    );
  }

  bool _isDenied(CommandDecision decision) => switch (decision) {
    CommandDecision.allow => false,
    CommandDecision.review => denyOnReview,
    CommandDecision.deny => true,
  };

  /// Whether `command_shield` classified the command as a critical-severity
  /// denial — the worst category, which [neverConfirmCritical] protects.
  bool _criticalDeny(CommandReview review) =>
      review.result.decision == CommandDecision.deny &&
      review.result.securityLevel == SecurityLevel.critical;

  String _denialReason(
    CommandDecision decision,
    CommandReview review,
    bool fromFilter,
    bool criticalBlocked,
  ) {
    final base = _denialBase(decision, review, fromFilter);
    // Note when a confirm callback existed but was bypassed by the critical
    // safety floor, so the audit trail explains why it could not be overridden.
    if (criticalBlocked && confirm != null) {
      return '$base (critical severity: confirmation disabled)';
    }
    return base;
  }

  String _denialBase(
    CommandDecision decision,
    CommandReview review,
    bool fromFilter,
  ) {
    if (fromFilter) {
      // The filter overrode command_shield's verdict; attribute it to the
      // filter and only attach the analysis findings when there are any.
      return review.result.findings.isEmpty
          ? 'command denied by the guard filter'
          : 'command denied by the guard filter (${review.explanation})';
    }
    return switch (decision) {
      CommandDecision.deny =>
        'command denied by command_shield: ${review.explanation}',
      CommandDecision.review =>
        'command flagged for review by command_shield: ${review.explanation}',
      // Unreachable: a non-filter allow is never a denial.
      CommandDecision.allow => 'command denied by the guard',
    };
  }

  String _overrideNote(CommandReview review) =>
      'execution confirmed despite denial: ${review.explanation}';
}
