/// Shared behaviour for sandboxed [FileSystemEntity] implementations.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../context.dart';
import '../events.dart';
import '../policy.dart';
import 'sandbox_directory.dart';
import 'sandbox_file.dart';
import 'sandbox_link.dart';

/// Wraps a native entity (real path inside the root) into its sandboxed
/// equivalent. Used when delegated operations hand back native entities (e.g.
/// `Directory.list`, `rename`, `parent`).
FileSystemEntity wrapEntity(SandboxContext ctx, FileSystemEntity raw) {
  final realPath = raw.path;
  if (raw is File) return SandboxFile.trusted(ctx, realPath);
  if (raw is Directory) return SandboxDirectory.trusted(ctx, realPath);
  if (raw is Link) return SandboxLink.trusted(ctx, realPath);
  // Unknown subtype: treat as a generic file handle.
  return SandboxFile.trusted(ctx, realPath);
}

/// Mixin providing the [FileSystemEntity] surface common to files, directories
/// and links. Concrete classes supply [context], [realPath] and the native
/// [rawEntity] delegate, plus their type-specific members (`rename`, `absolute`,
/// `create`, ...).
mixin SandboxEntityMixin implements FileSystemEntity {
  /// The owning sandbox context.
  SandboxContext get context;

  /// The resolved, contained real path this entity points at.
  String get realPath;

  /// The native (non-sandboxed) delegate operating on [realPath].
  FileSystemEntity get rawEntity;

  @override
  String get path => realPath;

  @override
  Uri get uri => Uri.file(realPath);

  @override
  bool get isAbsolute => true;

  /// Runs symlink-containment + policy checks and emits an access event.
  void guard(SandboxAccessType type, AccessMode mode, {String? destination}) =>
      context.authorize(type, mode, realPath, destination: destination);

  @override
  Directory get parent {
    var parentPath = p.dirname(realPath);
    // Never let `parent` walk above the sandbox root.
    if (!p.equals(realPath, context.realRoot) &&
        !p.isWithin(context.realRoot, parentPath)) {
      parentPath = context.realRoot;
    }
    if (p.equals(realPath, context.realRoot)) {
      parentPath = context.realRoot;
    }
    return SandboxDirectory.trusted(context, parentPath);
  }

  @override
  Future<bool> exists() {
    guard(SandboxAccessType.stat, AccessMode.read);
    final e = rawEntity;
    if (e is File) return e.exists();
    if (e is Directory) return e.exists();
    if (e is Link) return e.exists();
    return Future.value(false);
  }

  @override
  bool existsSync() {
    guard(SandboxAccessType.stat, AccessMode.read);
    final e = rawEntity;
    if (e is File) return e.existsSync();
    if (e is Directory) return e.existsSync();
    if (e is Link) return e.existsSync();
    return false;
  }

  @override
  Future<FileStat> stat() {
    guard(SandboxAccessType.stat, AccessMode.read);
    return rawEntity.stat();
  }

  @override
  FileStat statSync() {
    guard(SandboxAccessType.stat, AccessMode.read);
    return rawEntity.statSync();
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    guard(SandboxAccessType.delete, AccessMode.delete);
    await rawEntity.delete(recursive: recursive);
    return this;
  }

  @override
  void deleteSync({bool recursive = false}) {
    guard(SandboxAccessType.delete, AccessMode.delete);
    rawEntity.deleteSync(recursive: recursive);
  }

  @override
  Future<String> resolveSymbolicLinks() async {
    guard(SandboxAccessType.read, AccessMode.read);
    return rawEntity.resolveSymbolicLinks();
  }

  @override
  String resolveSymbolicLinksSync() {
    guard(SandboxAccessType.read, AccessMode.read);
    return rawEntity.resolveSymbolicLinksSync();
  }

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) {
    guard(SandboxAccessType.read, AccessMode.read);
    return rawEntity.watch(events: events, recursive: recursive);
  }

  /// Resolves and validates a destination path supplied by the caller (for
  /// rename/copy). Throws on escape.
  String resolveDestination(String newPath) => context.resolve(newPath);
}
