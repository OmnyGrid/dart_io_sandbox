/// Policy layer: deterministic, pure rules describing what is allowed.
library;

import 'package:path/path.dart' as p;

import 'errors.dart';

/// The intent of a filesystem access, used for policy evaluation.
enum AccessMode {
  /// Reading content or metadata.
  read,

  /// Creating or modifying content.
  write,

  /// Removing an entity.
  delete,

  /// Renaming/moving an entity (treated as a write on both endpoints).
  rename,
}

/// A declarative, immutable sandbox policy.
///
/// Evaluation is a pure function of the policy plus the resolved real path, so
/// it is fully deterministic and unit-testable via [check].
///
/// Path matching rules:
///  * [deniedPaths] always win over [allowedPaths] (deny overrides allow).
///  * If [allowedPaths] is empty, any path inside the sandbox root is allowed
///    (subject to the deny list). If it is non-empty, a path must be within (or
///    equal to) one of the allowed entries.
///  * A path "matches" an entry when it equals the entry or is nested under it.
///
/// All path entries are compared after [p.normalize]; relative entries are
/// resolved against [root] by [SandboxPolicy.resolveAgainst].
class SandboxPolicy {
  /// When true, all writes, deletes and renames are denied.
  final bool readOnly;

  /// When true, [Sandbox.process] execution is permitted (still subject to the
  /// executable allowlist). When false, all process execution is denied.
  final bool allowProcess;

  /// When true, socket creation is permitted. When false (the default), all
  /// network access throws a [SandboxViolationError].
  final bool allowNetwork;

  /// Absolute (or root-relative) paths that may be accessed. Empty means
  /// "everything within the root".
  final List<String> allowedPaths;

  /// Absolute (or root-relative) paths that may never be accessed. Overrides
  /// [allowedPaths].
  final List<String> deniedPaths;

  /// Executables permitted by [Sandbox.process]. Matched by exact string or by
  /// basename. Empty means no executable is permitted even when [allowProcess]
  /// is true (fail-closed).
  final List<String> allowedExecutables;

  const SandboxPolicy({
    this.readOnly = false,
    this.allowProcess = false,
    this.allowNetwork = false,
    this.allowedPaths = const [],
    this.deniedPaths = const [],
    this.allowedExecutables = const [],
  });

  /// A maximally restrictive default: read-only, no process, no network.
  static const SandboxPolicy restrictive = SandboxPolicy(readOnly: true);

  /// Read-write within the root, no process, no network.
  static const SandboxPolicy readWrite = SandboxPolicy();

  /// Returns a copy of this policy with every allow/deny path entry passed
  /// through [transform]. Used at sandbox creation to canonicalize entries into
  /// the same (symlink-resolved, root-relative) space as the resolved real root,
  /// so policy matching lines up with resolved real paths.
  SandboxPolicy mapPaths(String Function(String entry) transform) {
    return SandboxPolicy(
      readOnly: readOnly,
      allowProcess: allowProcess,
      allowNetwork: allowNetwork,
      allowedPaths: allowedPaths.map(transform).toList(growable: false),
      deniedPaths: deniedPaths.map(transform).toList(growable: false),
      allowedExecutables: allowedExecutables,
    );
  }

  /// Combines this policy with a [parent] policy so the result is never more
  /// permissive than the parent. Used for nested sandboxes.
  SandboxPolicy intersect(SandboxPolicy parent) {
    return SandboxPolicy(
      readOnly: readOnly || parent.readOnly,
      allowProcess: allowProcess && parent.allowProcess,
      allowNetwork: allowNetwork && parent.allowNetwork,
      // The union of both deny lists.
      deniedPaths: [...deniedPaths, ...parent.deniedPaths],
      // Keep this sandbox's allow list (already confined to the nested root);
      // the parent deny list still applies on top.
      allowedPaths: allowedPaths,
      // Only executables allowed by *both* layers.
      allowedExecutables: parent.allowedExecutables.isEmpty
          ? allowedExecutables
          : allowedExecutables
                .where((e) => parent.allowedExecutables.contains(e))
                .toList(growable: false),
    );
  }

  /// Returns true when [path] equals [entry] or is nested under it.
  static bool _matches(String entry, String path) =>
      p.equals(entry, path) || p.isWithin(entry, path);

  /// Deterministically evaluates an access. Throws [SandboxPolicyError] when
  /// denied; returns normally when allowed.
  ///
  /// [realPath] must already be the resolved, normalized real path (this method
  /// does not perform containment checks against the root — that is the
  /// resolver's job).
  void check(AccessMode mode, String realPath) {
    final denied = denyReason(mode, realPath);
    if (denied != null) {
      throw SandboxPolicyError(realPath, denied);
    }
  }

  /// Returns the reason an access would be denied, or `null` if allowed. Pure
  /// and side-effect free, which makes policy logic trivial to unit test.
  String? denyReason(AccessMode mode, String realPath) {
    final isWrite = mode != AccessMode.read;
    if (readOnly && isWrite) {
      return 'policy is read-only; ${mode.name} is not permitted';
    }
    // Deny overrides allow.
    for (final d in deniedPaths) {
      if (_matches(d, realPath)) {
        return 'path is covered by deny list entry "$d"';
      }
    }
    if (allowedPaths.isNotEmpty) {
      final ok = allowedPaths.any((a) => _matches(a, realPath));
      if (!ok) {
        return 'path is not covered by any allow list entry';
      }
    }
    return null;
  }

  /// Whether [executable] is permitted by the executable allowlist. Matches by
  /// exact string or basename.
  bool allowsExecutable(String executable) {
    if (allowedExecutables.isEmpty) return false;
    final base = p.basename(executable);
    return allowedExecutables.contains(executable) ||
        allowedExecutables.contains(base);
  }
}
