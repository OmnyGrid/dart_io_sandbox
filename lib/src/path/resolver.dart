/// Path resolution layer: turns a caller-supplied path into a validated real
/// path guaranteed to live inside the sandbox root, including runtime symlink
/// containment.
library;

import 'package:path/path.dart' as p;

import '../errors.dart';
import 'validator.dart';

/// Resolves and validates paths for a single sandbox.
///
/// It depends only on the (already canonicalized) [root], a callback that
/// reports the current virtual working directory, and two raw filesystem
/// callbacks. The raw callbacks must bypass the sandbox (operate on the real
/// filesystem) so that symlink resolution does not recurse back through the
/// interception layer.
class PathResolver {
  /// The canonical, absolute, symlink-resolved sandbox root.
  final String root;

  /// Returns the current virtual working directory (a real path within [root]).
  final String Function() currentDirectory;

  /// Real-filesystem `exists` check (file, dir or link), bypassing the sandbox.
  final bool Function(String path) rawExists;

  /// Real-filesystem symlink resolution, bypassing the sandbox. Must throw if
  /// the path does not exist.
  final String Function(String path) rawResolveSymbolicLinks;

  PathResolver({
    required this.root,
    required this.currentDirectory,
    required this.rawExists,
    required this.rawResolveSymbolicLinks,
  });

  /// Resolves [input] to an absolute real path and verifies it is lexically
  /// contained within [root]. Does not touch the filesystem.
  ///
  /// Throws [SandboxPathError] for malformed input and [SandboxViolationError]
  /// when the path escapes the root.
  String resolve(String input) {
    final real = resolveLexical(
      root: root,
      cwd: currentDirectory(),
      input: input,
    );
    assertContained(root: root, realPath: real, attempted: input);
    return real;
  }

  /// Like [resolve], but additionally follows symlinks on the existing portion
  /// of the path and verifies the canonical target is still inside [root].
  ///
  /// This is the check that defeats symlink-escape attacks: a link whose *name*
  /// is inside the root but whose *target* points outside is rejected here, at
  /// access time (links can be created after the sandbox starts).
  ///
  /// For a not-yet-existing leaf (e.g. a file about to be created), the nearest
  /// existing ancestor is canonicalized and the remaining segments are appended
  /// lexically before the containment check.
  String resolveReal(String input) {
    final lexical = resolve(input);
    final canonical = _canonicalize(lexical);
    assertContained(root: root, realPath: canonical, attempted: input);
    return lexical;
  }

  /// Canonicalizes [path] by resolving symlinks on its longest existing prefix.
  String _canonicalize(String path) => canonicalizePath(
    path,
    rawExists: rawExists,
    rawResolveSymbolicLinks: rawResolveSymbolicLinks,
  );
}

/// Resolves symlinks on the longest existing prefix of [path], leaving any
/// not-yet-existing trailing segments untouched. Returns [path] unchanged if no
/// ancestor exists. Pure aside from the two supplied raw-filesystem callbacks.
String canonicalizePath(
  String path, {
  required bool Function(String path) rawExists,
  required String Function(String path) rawResolveSymbolicLinks,
}) {
  if (rawExists(path)) {
    return rawResolveSymbolicLinks(path);
  }
  final segments = <String>[];
  var current = path;
  while (true) {
    final parent = p.dirname(current);
    if (parent == current) {
      // Reached the filesystem root without finding an existing ancestor.
      return path;
    }
    segments.add(p.basename(current));
    current = parent;
    if (rawExists(current)) {
      final canonicalParent = rawResolveSymbolicLinks(current);
      return p.joinAll([canonicalParent, ...segments.reversed]);
    }
  }
}
