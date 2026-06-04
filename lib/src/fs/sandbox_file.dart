/// Sandboxed [File] implementation.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../context.dart';
import '../events.dart';
import '../policy.dart';
import 'sandbox_entity.dart';

/// A [File] whose every operation is checked against the sandbox policy and
/// confined to the sandbox root. All work is delegated to a native [File] bound
/// to the already-resolved real path.
class SandboxFile with SandboxEntityMixin implements File {
  @override
  final SandboxContext context;

  @override
  final String realPath;

  late final File _raw = context.rawFile(realPath);

  /// Creates a sandboxed file from an already-resolved, contained real path.
  SandboxFile.trusted(this.context, this.realPath);

  @override
  FileSystemEntity get rawEntity => _raw;

  AccessMode _modeFor(FileMode mode) =>
      mode == FileMode.read ? AccessMode.read : AccessMode.write;

  @override
  File get absolute => SandboxFile.trusted(context, realPath);

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    guard(SandboxAccessType.create, AccessMode.write);
    await _raw.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  void createSync({bool recursive = false, bool exclusive = false}) {
    guard(SandboxAccessType.create, AccessMode.write);
    _raw.createSync(recursive: recursive, exclusive: exclusive);
  }

  @override
  Future<File> rename(String newPath) async {
    final dest = resolveDestination(newPath);
    guard(SandboxAccessType.rename, AccessMode.rename, destination: dest);
    context.authorize(SandboxAccessType.rename, AccessMode.write, dest);
    await _raw.rename(dest);
    return SandboxFile.trusted(context, dest);
  }

  @override
  File renameSync(String newPath) {
    final dest = resolveDestination(newPath);
    guard(SandboxAccessType.rename, AccessMode.rename, destination: dest);
    context.authorize(SandboxAccessType.rename, AccessMode.write, dest);
    _raw.renameSync(dest);
    return SandboxFile.trusted(context, dest);
  }

  @override
  Future<File> copy(String newPath) async {
    final dest = resolveDestination(newPath);
    guard(SandboxAccessType.read, AccessMode.read);
    context.authorize(SandboxAccessType.write, AccessMode.write, dest);
    await _raw.copy(dest);
    return SandboxFile.trusted(context, dest);
  }

  @override
  File copySync(String newPath) {
    final dest = resolveDestination(newPath);
    guard(SandboxAccessType.read, AccessMode.read);
    context.authorize(SandboxAccessType.write, AccessMode.write, dest);
    _raw.copySync(dest);
    return SandboxFile.trusted(context, dest);
  }

  @override
  Future<int> length() {
    guard(SandboxAccessType.read, AccessMode.read);
    return _raw.length();
  }

  @override
  int lengthSync() {
    guard(SandboxAccessType.read, AccessMode.read);
    return _raw.lengthSync();
  }

  @override
  Future<DateTime> lastAccessed() {
    guard(SandboxAccessType.stat, AccessMode.read);
    return _raw.lastAccessed();
  }

  @override
  DateTime lastAccessedSync() {
    guard(SandboxAccessType.stat, AccessMode.read);
    return _raw.lastAccessedSync();
  }

  @override
  Future<void> setLastAccessed(DateTime time) {
    guard(SandboxAccessType.write, AccessMode.write);
    return _raw.setLastAccessed(time);
  }

  @override
  void setLastAccessedSync(DateTime time) {
    guard(SandboxAccessType.write, AccessMode.write);
    _raw.setLastAccessedSync(time);
  }

  @override
  Future<DateTime> lastModified() {
    guard(SandboxAccessType.stat, AccessMode.read);
    return _raw.lastModified();
  }

  @override
  DateTime lastModifiedSync() {
    guard(SandboxAccessType.stat, AccessMode.read);
    return _raw.lastModifiedSync();
  }

  @override
  Future<void> setLastModified(DateTime time) {
    guard(SandboxAccessType.write, AccessMode.write);
    return _raw.setLastModified(time);
  }

  @override
  void setLastModifiedSync(DateTime time) {
    guard(SandboxAccessType.write, AccessMode.write);
    _raw.setLastModifiedSync(time);
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) {
    guard(SandboxAccessType.read, _modeFor(mode));
    return _raw.open(mode: mode);
  }

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    guard(SandboxAccessType.read, _modeFor(mode));
    return _raw.openSync(mode: mode);
  }

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    guard(SandboxAccessType.read, AccessMode.read);
    return _raw.openRead(start, end);
  }

  @override
  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) {
    guard(SandboxAccessType.write, _modeFor(mode));
    return _raw.openWrite(mode: mode, encoding: encoding);
  }

  @override
  Future<Uint8List> readAsBytes() {
    guard(SandboxAccessType.read, AccessMode.read);
    return _raw.readAsBytes();
  }

  @override
  Uint8List readAsBytesSync() {
    guard(SandboxAccessType.read, AccessMode.read);
    return _raw.readAsBytesSync();
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) {
    guard(SandboxAccessType.read, AccessMode.read);
    return _raw.readAsString(encoding: encoding);
  }

  @override
  String readAsStringSync({Encoding encoding = utf8}) {
    guard(SandboxAccessType.read, AccessMode.read);
    return _raw.readAsStringSync(encoding: encoding);
  }

  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) {
    guard(SandboxAccessType.read, AccessMode.read);
    return _raw.readAsLines(encoding: encoding);
  }

  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) {
    guard(SandboxAccessType.read, AccessMode.read);
    return _raw.readAsLinesSync(encoding: encoding);
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    guard(SandboxAccessType.write, AccessMode.write);
    await _raw.writeAsBytes(bytes, mode: mode, flush: flush);
    return this;
  }

  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    guard(SandboxAccessType.write, AccessMode.write);
    _raw.writeAsBytesSync(bytes, mode: mode, flush: flush);
  }

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    guard(SandboxAccessType.write, AccessMode.write);
    await _raw.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
    return this;
  }

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    guard(SandboxAccessType.write, AccessMode.write);
    _raw.writeAsStringSync(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
  }

  @override
  String toString() => "SandboxFile: '$realPath'";
}
