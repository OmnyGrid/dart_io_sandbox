/// Error hierarchy for the sandbox.
///
/// Every error carries the *attempted* path or action and a human-readable
/// [reason], so callers and audit logs can see exactly what was denied and why.
library;

/// Base class for all sandbox failures.
///
/// This is an [Error] (not an [Exception]) because a violation indicates a
/// programming/security problem in the sandboxed code rather than an expected,
/// recoverable condition. Callers that want to handle violations gracefully can
/// still `catch` it.
abstract class SandboxError extends Error {
  /// The path or action that was attempted (e.g. `/etc/passwd`, `echo`).
  final String attempted;

  /// Why the attempt was denied.
  final String reason;

  SandboxError(this.attempted, this.reason);

  /// A short, stable label used in messages (e.g. `SandboxViolation`).
  String get label;

  @override
  String toString() => '$label: $reason (attempted: "$attempted")';
}

/// Thrown when an operation would escape the sandbox root.
///
/// Covers `..` traversal, absolute-path escape, symlink escape, and (when
/// network access is disabled) socket creation.
class SandboxViolationError extends SandboxError {
  SandboxViolationError(super.attempted, super.reason);

  @override
  String get label => 'SandboxViolation';

  /// Convenience constructor for a path that resolves outside the root.
  factory SandboxViolationError.escape(String attempted, String root) =>
      SandboxViolationError(
        attempted,
        'resolved path escapes sandbox root "$root"',
      );

  /// Convenience constructor for a blocked network operation.
  factory SandboxViolationError.network(String attempted) =>
      SandboxViolationError(
        attempted,
        'network access is disabled by the sandbox policy',
      );
}

/// Thrown when a path is malformed or cannot be resolved safely.
class SandboxPathError extends SandboxError {
  SandboxPathError(super.attempted, super.reason);

  @override
  String get label => 'SandboxPathError';
}

/// Thrown when an operation is denied by the [SandboxPolicy] (read-only mode,
/// deny list, or a non-allowed path).
class SandboxPolicyError extends SandboxError {
  SandboxPolicyError(super.attempted, super.reason);

  @override
  String get label => 'SandboxPolicyError';
}

/// Thrown when process execution is denied (disabled, not on the allowlist, or
/// containing a blocked shell pattern).
class SandboxProcessDeniedError extends SandboxError {
  SandboxProcessDeniedError(super.attempted, super.reason);

  @override
  String get label => 'SandboxProcessDenied';
}
