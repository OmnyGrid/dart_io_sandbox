/// Sandboxed [Directory] implementation.
library;

import 'dart:io';

import '../context.dart';
import '../events.dart';
import '../policy.dart';
import 'sandbox_entity.dart';

/// A [Directory] confined to the sandbox root. Listing yields sandboxed
/// entities, and `createTemp`/`rename` results stay within the root.
class SandboxDirectory with SandboxEntityMixin implements Directory {
  @override
  final SandboxContext context;

  @override
  final String realPath;

  late final Directory _raw = context.rawDirectory(realPath);

  /// Creates a sandboxed directory from an already-resolved real path.
  SandboxDirectory.trusted(this.context, this.realPath);

  @override
  FileSystemEntity get rawEntity => _raw;

  @override
  Uri get uri => Uri.directory(realPath);

  @override
  Directory get absolute => SandboxDirectory.trusted(context, realPath);

  @override
  Future<Directory> create({bool recursive = false}) async {
    guard(SandboxAccessType.create, AccessMode.write);
    await _raw.create(recursive: recursive);
    return this;
  }

  @override
  void createSync({bool recursive = false}) {
    guard(SandboxAccessType.create, AccessMode.write);
    _raw.createSync(recursive: recursive);
  }

  @override
  Future<Directory> createTemp([String? prefix]) async {
    guard(SandboxAccessType.create, AccessMode.write);
    final created = await _raw.createTemp(prefix);
    return SandboxDirectory.trusted(context, created.path);
  }

  @override
  Directory createTempSync([String? prefix]) {
    guard(SandboxAccessType.create, AccessMode.write);
    final created = _raw.createTempSync(prefix);
    return SandboxDirectory.trusted(context, created.path);
  }

  @override
  Future<Directory> rename(String newPath) async {
    final dest = resolveDestination(newPath);
    guard(SandboxAccessType.rename, AccessMode.rename, destination: dest);
    context.authorize(SandboxAccessType.rename, AccessMode.write, dest);
    await _raw.rename(dest);
    return SandboxDirectory.trusted(context, dest);
  }

  @override
  Directory renameSync(String newPath) {
    final dest = resolveDestination(newPath);
    guard(SandboxAccessType.rename, AccessMode.rename, destination: dest);
    context.authorize(SandboxAccessType.rename, AccessMode.write, dest);
    _raw.renameSync(dest);
    return SandboxDirectory.trusted(context, dest);
  }

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    guard(SandboxAccessType.list, AccessMode.read);
    return _raw
        .list(recursive: recursive, followLinks: followLinks)
        .map((e) => wrapEntity(context, e));
  }

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) {
    guard(SandboxAccessType.list, AccessMode.read);
    return _raw
        .listSync(recursive: recursive, followLinks: followLinks)
        .map((e) => wrapEntity(context, e))
        .toList();
  }

  @override
  String toString() => "SandboxDirectory: '$realPath'";
}
