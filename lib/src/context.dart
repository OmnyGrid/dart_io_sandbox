/// Per-sandbox runtime state, shared by every sandboxed entity and the process
/// manager. One [SandboxContext] exists per active [Sandbox.run] call and lives
/// on the installed [SandboxIOOverrides] instance.
library;

import 'dart:io';

import 'errors.dart';
import 'events.dart';
import 'path/resolver.dart';
import 'policy.dart';

/// Mutable, zone-scoped state for a running sandbox.
class SandboxContext {
  /// Canonical (symlink-resolved), absolute root directory.
  final String realRoot;

  /// The effective, path-resolved policy (already intersected with any parent).
  final SandboxPolicy policy;

  /// Optional access observer.
  final SandboxAccessHook? onAccess;

  /// The enclosing sandbox context, if this is a nested sandbox.
  final SandboxContext? parent;

  /// Raw (non-sandboxed) filesystem constructors, wired by the overrides layer.
  /// These bypass interception so symlink resolution and delegation do not
  /// recurse.
  final File Function(String) rawFile;
  final Directory Function(String) rawDirectory;
  final Link Function(String) rawLink;
  final FileSystemEntityType Function(String path, bool followLinks)
  rawTypeSync;

  /// Virtual current working directory (a real path inside [realRoot]).
  String cwd;

  late final PathResolver resolver;

  SandboxContext({
    required this.realRoot,
    required this.policy,
    required this.onAccess,
    required this.parent,
    required this.rawFile,
    required this.rawDirectory,
    required this.rawLink,
    required this.rawTypeSync,
  }) : cwd = realRoot {
    resolver = PathResolver(
      root: realRoot,
      currentDirectory: () => cwd,
      rawExists: (path) =>
          rawTypeSync(path, false) != FileSystemEntityType.notFound,
      rawResolveSymbolicLinks: (path) =>
          rawFile(path).resolveSymbolicLinksSync(),
    );
  }

  /// Emits an event to the hook, if one is registered.
  void emit(SandboxAccessEvent event) => onAccess?.call(event);

  /// Resolves [input] to a real path, enforcing both lexical containment and
  /// runtime symlink containment. Throws on escape.
  String resolve(String input) => resolver.resolveReal(input);

  /// Runs the full guard for a single-path operation: symlink containment
  /// followed by policy evaluation. Emits the corresponding access event and
  /// throws on denial.
  ///
  /// [realPath] must already be resolved (e.g. an entity's own path).
  void authorize(
    SandboxAccessType type,
    AccessMode mode,
    String realPath, {
    String? destination,
  }) {
    // Re-check symlink containment at access time (links can be created after
    // the entity object was constructed).
    resolver.resolveReal(realPath);
    final reason = policy.denyReason(mode, realPath);
    if (reason != null) {
      emit(
        SandboxAccessEvent(
          type: type,
          target: realPath,
          allowed: false,
          reason: reason,
          destination: destination,
        ),
      );
      throw SandboxPolicyError(realPath, reason);
    }
    emit(
      SandboxAccessEvent(
        type: type,
        target: realPath,
        allowed: true,
        destination: destination,
      ),
    );
  }
}
