/// The sandbox entry point and the [IOOverrides] interception layer.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'context.dart';
import 'errors.dart';
import 'events.dart';
import 'fs/sandbox_directory.dart';
import 'fs/sandbox_file.dart';
import 'fs/sandbox_link.dart';
import 'path/resolver.dart';
import 'path/validator.dart';
import 'policy.dart';
import 'process/sandbox_process.dart';

/// A concrete [IOOverrides] with no overrides: every method falls through to the
/// real, native `dart:io` behaviour. Used to build delegates and to set up
/// sandbox roots without re-entering the interception layer.
base class _NativeOverrides extends IOOverrides {}

final IOOverrides _native = _NativeOverrides();

/// Returns the sandbox context active in the current zone, or `null` if no
/// sandbox is installed.
SandboxContext? get currentSandboxContext {
  final overrides = IOOverrides.current;
  return overrides is SandboxIOOverrides ? overrides.context : null;
}

/// The [IOOverrides] implementation that redirects all `dart:io` filesystem
/// construction through the sandbox. Entity *methods* are policed by the
/// returned [SandboxFile]/[SandboxDirectory]/[SandboxLink]; this class handles
/// construction plus the standalone overrides (`stat`, `fseGetType`,
/// `identical`, `watch`) and the network gate.
base class SandboxIOOverrides extends IOOverrides {
  /// The sandbox this override set serves.
  final SandboxContext context;

  SandboxIOOverrides(this.context);

  @override
  File createFile(String path) =>
      SandboxFile.trusted(context, context.resolve(path));

  @override
  Directory createDirectory(String path) =>
      SandboxDirectory.trusted(context, context.resolve(path));

  @override
  Link createLink(String path) =>
      SandboxLink.trusted(context, context.resolve(path));

  @override
  Directory getCurrentDirectory() =>
      SandboxDirectory.trusted(context, context.cwd);

  @override
  void setCurrentDirectory(String path) {
    final real = context.resolve(path);
    if (super.fseGetTypeSync(real, true) != FileSystemEntityType.directory) {
      throw SandboxPathError(path, 'cannot cd into a non-directory');
    }
    context.cwd = real;
  }

  @override
  Directory getSystemTempDirectory() {
    final tmp = p.join(context.realRoot, '.tmp');
    super.createDirectory(tmp).createSync(recursive: true);
    return SandboxDirectory.trusted(context, tmp);
  }

  @override
  Future<FileStat> stat(String path) {
    final real = context.resolve(path);
    context.authorize(SandboxAccessType.stat, AccessMode.read, real);
    return super.stat(real);
  }

  @override
  FileStat statSync(String path) {
    final real = context.resolve(path);
    context.authorize(SandboxAccessType.stat, AccessMode.read, real);
    return super.statSync(real);
  }

  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) {
    final real = context.resolve(path);
    context.authorize(SandboxAccessType.stat, AccessMode.read, real);
    return super.fseGetType(real, followLinks);
  }

  @override
  FileSystemEntityType fseGetTypeSync(String path, bool followLinks) {
    final real = context.resolve(path);
    context.authorize(SandboxAccessType.stat, AccessMode.read, real);
    return super.fseGetTypeSync(real, followLinks);
  }

  @override
  Future<bool> fseIdentical(String path1, String path2) {
    final r1 = context.resolve(path1);
    final r2 = context.resolve(path2);
    return super.fseIdentical(r1, r2);
  }

  @override
  bool fseIdenticalSync(String path1, String path2) {
    final r1 = context.resolve(path1);
    final r2 = context.resolve(path2);
    return super.fseIdenticalSync(r1, r2);
  }

  @override
  Stream<FileSystemEvent> fsWatch(String path, int events, bool recursive) {
    final real = context.resolve(path);
    context.authorize(SandboxAccessType.read, AccessMode.read, real);
    return super.fsWatch(real, events, recursive);
  }

  // --- Network gate -------------------------------------------------------

  @override
  Future<Socket> socketConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) {
    _guardNetwork('$host:$port');
    return super.socketConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      timeout: timeout,
    );
  }

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
  }) {
    _guardNetwork('$host:$port');
    return super.socketStartConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
    );
  }

  @override
  Future<ServerSocket> serverSocketBind(
    address,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) {
    _guardNetwork('$address:$port');
    return super.serverSocketBind(
      address,
      port,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
    );
  }

  void _guardNetwork(String target) {
    if (!context.policy.allowNetwork) {
      context.emit(
        SandboxAccessEvent(
          type: SandboxAccessType.network,
          target: target,
          allowed: false,
          reason: 'network access is disabled by the sandbox policy',
        ),
      );
      throw SandboxViolationError.network(target);
    }
    context.emit(
      SandboxAccessEvent(
        type: SandboxAccessType.network,
        target: target,
        allowed: true,
      ),
    );
  }
}

/// The public sandbox facade.
///
/// Use [Sandbox.run] to execute code with all `dart:io` filesystem access
/// confined to [root], and [Sandbox.process] to run allowlisted executables.
class Sandbox {
  Sandbox._();

  /// The process manager. Reads the active sandbox policy at call time, so it
  /// must be used inside a [Sandbox.run] body.
  static final SandboxProcessManager process = SandboxProcessManager();

  /// The sandbox context active in the current zone, or `null`.
  static SandboxContext? get current => currentSandboxContext;

  /// Runs [action] inside a sandbox rooted at [root].
  ///
  /// While [action] runs, every `dart:io` `File`/`Directory`/`Link` (and the
  /// related static helpers) is confined to [root]; escapes throw a
  /// [SandboxViolationError]. When called inside another sandbox the new one is
  /// nested: its root must live within the parent's root and its policy can
  /// never be more permissive than the parent's.
  static Future<T> run<T>({
    required String root,
    SandboxPolicy? policy,
    SandboxAccessHook? onAccess,
    required Future<T> Function() action,
  }) {
    final context = _createContext(
      root: root,
      policy: policy,
      onAccess: onAccess,
    );
    return IOOverrides.runWithIOOverrides(action, SandboxIOOverrides(context));
  }

  /// Convenience wrapper accepting a [SandboxConfig].
  static Future<T> runConfig<T>(
    SandboxConfig config,
    Future<T> Function() action,
  ) => run(
    root: config.root,
    policy: config.policy,
    onAccess: config.onAccess,
    action: action,
  );

  static SandboxContext _createContext({
    required String root,
    SandboxPolicy? policy,
    SandboxAccessHook? onAccess,
  }) => createSandboxContext(root: root, policy: policy, onAccess: onAccess);
}

/// Builds a [SandboxContext] for [root], honouring any enclosing sandbox
/// (nesting) discovered via [currentSandboxContext]. Exposed for the
/// `package:file` adapter, which needs to construct an [SandboxIOOverrides]
/// without entering [Sandbox.run].
SandboxContext createSandboxContext({
  required String root,
  SandboxPolicy? policy,
  SandboxAccessHook? onAccess,
}) {
  final parent = currentSandboxContext;

  // Resolve the requested root. When nested, route through the parent so the
  // nested root is validated to live within the parent's root.
  final String requestedReal = parent != null
      ? parent.resolve(root)
      : p.normalize(p.absolute(root));

  // Ensure the root directory exists, then canonicalize it (resolve symlinks)
  // so all later containment checks compare against the canonical form.
  final dir = _native.createDirectory(requestedReal);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final realRoot = dir.resolveSymbolicLinksSync();

  if (parent != null && !isContained(parent.realRoot, realRoot)) {
    throw SandboxViolationError.escape(root, parent.realRoot);
  }

  // Canonicalize policy path entries the same way the root is canonicalized,
  // so allow/deny matching lines up with resolved real paths (this matters on
  // systems where the root contains a symlink, e.g. /tmp -> /private/tmp).
  bool rawExists(String path) =>
      _native.fseGetTypeSync(path, false) != FileSystemEntityType.notFound;
  String rawResolve(String path) =>
      _native.createFile(path).resolveSymbolicLinksSync();
  String canon(String entry) {
    final abs = p.isAbsolute(entry) ? entry : p.join(realRoot, entry);
    return canonicalizePath(
      p.normalize(abs),
      rawExists: rawExists,
      rawResolveSymbolicLinks: rawResolve,
    );
  }

  var effective = (policy ?? const SandboxPolicy()).mapPaths(canon);
  if (parent != null) {
    effective = effective.intersect(parent.policy);
  }

  return SandboxContext(
    realRoot: realRoot,
    policy: effective,
    onAccess: onAccess ?? parent?.onAccess,
    parent: parent,
    rawFile: _native.createFile,
    rawDirectory: _native.createDirectory,
    rawLink: _native.createLink,
    rawTypeSync: _native.fseGetTypeSync,
  );
}
