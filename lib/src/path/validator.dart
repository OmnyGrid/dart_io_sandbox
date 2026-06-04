/// Pure path-containment helpers. No filesystem access; fully deterministic and
/// unit-testable in isolation.
library;

import 'package:path/path.dart' as p;

import '../errors.dart';

/// Returns true when [path] is equal to [root] or nested anywhere beneath it.
///
/// Both arguments are normalized first so `.`/`..` segments are collapsed.
bool isContained(String root, String path) {
  final r = p.normalize(root);
  final c = p.normalize(path);
  return p.equals(r, c) || p.isWithin(r, c);
}

/// Resolves [input] against [root] and the virtual [cwd], collapsing `.` and
/// `..` segments lexically, and returns the absolute real path.
///
/// Resolution model (a *jail*, not a chroot):
///  * A relative path is joined onto [cwd].
///  * An absolute path is used as-is.
///  * The result is normalized; `..` is applied lexically.
///
/// This does **not** perform the containment check — call [assertContained] (or
/// use the resolver) afterwards. Splitting the two keeps this function pure and
/// makes "what does this path resolve to" independently testable.
String resolveLexical({
  required String root,
  required String cwd,
  required String input,
}) {
  if (input.isEmpty) {
    throw SandboxPathError(input, 'empty path is not allowed');
  }
  if (input.contains('\x00')) {
    throw SandboxPathError(input, 'path contains a null byte');
  }
  final base = p.isAbsolute(input) ? input : p.join(cwd, input);
  return p.normalize(base);
}

/// Throws [SandboxViolationError] unless [realPath] is contained within [root].
void assertContained({
  required String root,
  required String realPath,
  required String attempted,
}) {
  if (!isContained(root, realPath)) {
    throw SandboxViolationError.escape(attempted, root);
  }
}
