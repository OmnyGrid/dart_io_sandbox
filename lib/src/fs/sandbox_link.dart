/// Sandboxed [Link] implementation.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../context.dart';
import '../errors.dart';
import '../events.dart';
import '../policy.dart';
import '../path/validator.dart';
import 'sandbox_entity.dart';

/// A symbolic [Link] confined to the sandbox. Creating or updating a link whose
/// target would point outside the root is rejected, which prevents using links
/// to escape the jail.
class SandboxLink with SandboxEntityMixin implements Link {
  @override
  final SandboxContext context;

  @override
  final String realPath;

  late final Link _raw = context.rawLink(realPath);

  /// Creates a sandboxed link from an already-resolved real path.
  SandboxLink.trusted(this.context, this.realPath);

  @override
  FileSystemEntity get rawEntity => _raw;

  @override
  Link get absolute => SandboxLink.trusted(context, realPath);

  /// Rejects a link target that would resolve outside the sandbox root.
  void _validateTarget(String target) {
    final base = p.isAbsolute(target)
        ? target
        : p.join(p.dirname(realPath), target);
    final resolved = p.normalize(base);
    if (!isContained(context.realRoot, resolved)) {
      throw SandboxViolationError(
        target,
        'link target escapes sandbox root "${context.realRoot}"',
      );
    }
  }

  @override
  Future<Link> create(String target, {bool recursive = false}) async {
    _validateTarget(target);
    guard(SandboxAccessType.create, AccessMode.write);
    await _raw.create(target, recursive: recursive);
    return this;
  }

  @override
  void createSync(String target, {bool recursive = false}) {
    _validateTarget(target);
    guard(SandboxAccessType.create, AccessMode.write);
    _raw.createSync(target, recursive: recursive);
  }

  @override
  Future<Link> update(String target) async {
    _validateTarget(target);
    guard(SandboxAccessType.write, AccessMode.write);
    await _raw.update(target);
    return this;
  }

  @override
  void updateSync(String target) {
    _validateTarget(target);
    guard(SandboxAccessType.write, AccessMode.write);
    _raw.updateSync(target);
  }

  @override
  Future<String> target() {
    guard(SandboxAccessType.read, AccessMode.read);
    return _raw.target();
  }

  @override
  String targetSync() {
    guard(SandboxAccessType.read, AccessMode.read);
    return _raw.targetSync();
  }

  @override
  Future<Link> rename(String newPath) async {
    final dest = resolveDestination(newPath);
    guard(SandboxAccessType.rename, AccessMode.rename, destination: dest);
    context.authorize(SandboxAccessType.rename, AccessMode.write, dest);
    await _raw.rename(dest);
    return SandboxLink.trusted(context, dest);
  }

  @override
  Link renameSync(String newPath) {
    final dest = resolveDestination(newPath);
    guard(SandboxAccessType.rename, AccessMode.rename, destination: dest);
    context.authorize(SandboxAccessType.rename, AccessMode.write, dest);
    _raw.renameSync(dest);
    return SandboxLink.trusted(context, dest);
  }

  @override
  String toString() => "SandboxLink: '$realPath'";
}
