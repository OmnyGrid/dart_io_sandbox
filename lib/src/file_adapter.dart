/// Optional `package:file` integration.
///
/// [SandboxFileSystem] exposes a sandbox as a `package:file` [FileSystem]. It
/// works because `LocalFileSystem` captures its `dart:io` delegate at
/// entity-construction time: if `file()`/`directory()`/`link()` run inside the
/// sandbox zone, the returned entity is backed by a sandboxed `dart:io` entity
/// and stays confined for the rest of its life.
library;

import 'dart:io' show IOOverrides;

import 'package:file/file.dart';
import 'package:file/local.dart';

import 'config.dart';
import 'events.dart';
import 'policy.dart';
import 'sandbox.dart';

/// A `package:file` [FileSystem] confined to a sandbox.
///
/// Two modes:
///  * **Bound** ([SandboxFileSystem.bound]): owns its own sandbox overrides, so
///    it is confined no matter where it is used.
///  * **Ambient** (default constructor): forwards to the sandbox installed by
///    the enclosing [Sandbox.run]; using it outside a sandbox provides no
///    confinement.
class SandboxFileSystem extends ForwardingFileSystem {
  /// The bound overrides, or `null` for the ambient mode.
  final IOOverrides? _overrides;

  SandboxFileSystem._(this._overrides) : super(const LocalFileSystem());

  /// Forwards to whatever sandbox is installed in the current zone. Only
  /// confines access when used inside a [Sandbox.run] body.
  SandboxFileSystem() : this._(null);

  /// Creates a self-contained sandboxed file system from [config]. Every
  /// operation runs inside the bound sandbox, so confinement holds even outside
  /// a [Sandbox.run] body.
  factory SandboxFileSystem.bound({
    required String root,
    SandboxPolicy? policy,
    SandboxAccessHook? onAccess,
  }) {
    final context = createSandboxContext(
      root: root,
      policy: policy,
      onAccess: onAccess,
    );
    return SandboxFileSystem._(SandboxIOOverrides(context));
  }

  /// Convenience overload taking a [SandboxConfig].
  factory SandboxFileSystem.fromConfig(SandboxConfig config) =>
      SandboxFileSystem.bound(
        root: config.root,
        policy: config.policy,
        onAccess: config.onAccess,
      );

  /// Runs [body] inside the bound sandbox zone (a no-op for the ambient mode).
  R _z<R>(R Function() body) {
    final overrides = _overrides;
    return overrides == null
        ? body()
        : IOOverrides.runWithIOOverrides(body, overrides);
  }

  // Entity construction must happen in the zone so the captured dart:io
  // delegate is a sandboxed entity.

  @override
  File file(dynamic path) => _z(() => delegate.file(path));

  @override
  Directory directory(dynamic path) => _z(() => delegate.directory(path));

  @override
  Link link(dynamic path) => _z(() => delegate.link(path));

  @override
  Directory get currentDirectory => _z(() => delegate.currentDirectory);

  @override
  set currentDirectory(dynamic path) =>
      _z(() => delegate.currentDirectory = path);

  @override
  Directory get systemTempDirectory => _z(() => delegate.systemTempDirectory);

  @override
  Future<FileStat> stat(String path) => _z(() => delegate.stat(path));

  @override
  FileStat statSync(String path) => _z(() => delegate.statSync(path));

  @override
  Future<FileSystemEntityType> type(String path, {bool followLinks = true}) =>
      _z(() => delegate.type(path, followLinks: followLinks));

  @override
  FileSystemEntityType typeSync(String path, {bool followLinks = true}) =>
      _z(() => delegate.typeSync(path, followLinks: followLinks));

  @override
  Future<bool> identical(String path1, String path2) =>
      _z(() => delegate.identical(path1, path2));

  @override
  bool identicalSync(String path1, String path2) =>
      _z(() => delegate.identicalSync(path1, path2));
}
