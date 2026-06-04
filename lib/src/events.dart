/// Observability layer: every sandbox access produces a [SandboxAccessEvent].
library;

/// The kind of operation an access event describes.
enum SandboxAccessType {
  read,
  write,
  delete,
  rename,
  list,
  stat,

  /// Creating a file/directory/link entity.
  create,

  /// Process execution attempt.
  process,

  /// Network (socket) attempt.
  network,
}

/// A single observed access attempt against the sandbox.
///
/// Emitted for *both* allowed and denied attempts so a hook can build a
/// complete audit trail. Denied events carry a [reason].
class SandboxAccessEvent {
  /// What kind of operation was attempted.
  final SandboxAccessType type;

  /// The primary path or action involved (resolved real path for FS ops,
  /// executable name for process ops, `host:port` for network ops).
  final String target;

  /// Whether the attempt was permitted.
  final bool allowed;

  /// Why the attempt was denied; `null` when [allowed] is true.
  final String? reason;

  /// Secondary path for two-path operations (rename/copy destination).
  final String? destination;

  const SandboxAccessEvent({
    required this.type,
    required this.target,
    required this.allowed,
    this.reason,
    this.destination,
  });

  @override
  String toString() {
    final verdict = allowed ? 'ALLOW' : 'DENY';
    final dest = destination != null ? ' -> $destination' : '';
    final why = reason != null ? ' ($reason)' : '';
    return '[$verdict] ${type.name} $target$dest$why';
  }
}

/// Signature for an access hook.
typedef SandboxAccessHook = void Function(SandboxAccessEvent event);
