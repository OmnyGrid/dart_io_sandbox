/// A custom test-runner VM platform that spawns each suite in an isolate whose
/// bootstrap installs a `Sandbox.run` jail.
///
/// This mirrors the structure of `package:test_core`'s default `VMPlatform`,
/// but trimmed to the source-compiler isolate path and with a sandbox-wrapping
/// bootstrap (see `bootstrap.dart`). Registering it via `registerPlatformPlugin`
/// before the runner starts overrides the default VM platform, so `dart test`'s
/// globbing, tag/name filtering, concurrency and reporters are all reused while
/// every test body runs confined.
library;

// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:async/async.dart';
import 'package:path/path.dart' as p;
import 'package:stream_channel/isolate_channel.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test_api/backend.dart';
import 'package:test_core/src/runner/package_version.dart';
import 'package:test_core/src/runner/platform.dart';
import 'package:test_core/src/runner/plugin/environment.dart';
import 'package:test_core/src/runner/plugin/platform_helpers.dart';
import 'package:test_core/src/runner/runner_suite.dart';
import 'package:test_core/src/runner/suite.dart';
import 'package:test_core/src/util/package_config.dart';

import 'bootstrap.dart';
import 'package_config_merge.dart';
import 'sandbox_test_config.dart';

/// Loads VM test suites in isolates that each install the sandbox.
class SandboxVMPlatform extends PlatformPlugin {
  final SandboxTestConfig _config;
  final _closeMemo = AsyncMemoizer<void>();
  final Directory _tempDir = Directory.systemTemp.createTempSync(
    'dart_io_sandbox.vm.',
  );

  /// The package config the suite isolates are spawned with, built once and
  /// reused. See [_buildPackageConfig].
  Future<Uri>? _packageConfigMemo;

  SandboxVMPlatform(this._config);

  @override
  Future<RunnerSuite?> load(
    String path,
    SuitePlatform platform,
    SuiteConfiguration suiteConfig,
    Map<String, Object?> message,
  ) async {
    assert(platform.runtime == Runtime.vm);

    final receivePort = ReceivePort();
    Isolate isolate;
    try {
      isolate = await _spawnIsolate(
        path,
        receivePort.sendPort,
        suiteConfig.metadata,
      );
    } catch (_) {
      receivePort.close();
      rethrow;
    }

    final outerChannel = MultiChannel<Object?>(
      IsolateChannel.connectReceive(receivePort),
    );
    final cleanupCallbacks = <void Function()>[
      isolate.kill,
      outerChannel.sink.close,
    ];

    // The bootstrap sends the virtual control-channel id as its first message;
    // wire that virtual channel to deserializeSuite.
    final outerQueue = StreamQueue(outerChannel.stream);
    final channelId = (await outerQueue.next) as int;
    final channel = outerChannel
        .virtualChannel(channelId)
        .transformStream(
          StreamTransformer.fromHandlers(
            handleDone: (sink) {
              for (final fn in cleanupCallbacks) {
                fn();
              }
              sink.close();
            },
          ),
        );

    final controller = deserializeSuite(
      path,
      platform,
      suiteConfig,
      const PluginEnvironment(),
      channel.cast(),
      message,
    );
    return controller.suite;
  }

  Future<Isolate> _spawnIsolate(
    String path,
    SendPort message,
    Metadata suiteMetadata,
  ) async {
    final bootstrapUri = await _bootstrapFile(path, suiteMetadata);
    return Isolate.spawnUri(
      bootstrapUri,
      [],
      message,
      packageConfig: await _packageConfig,
      checked: true,
      debugName: 'dart_io_sandbox:$path',
    );
  }

  /// The package config used to spawn each suite isolate (memoized).
  Future<Uri> get _packageConfig =>
      _packageConfigMemo ??= _buildPackageConfig();

  /// Builds the package config for the suite isolates.
  ///
  /// The generated bootstrap imports `package:dart_io_sandbox` and
  /// `package:command_shield` on top of the project's test file (which imports
  /// `package:test`). The project under test need not depend on the sandbox
  /// packages, and the CLI's own config need not contain `test` (it is a
  /// dev-dependency, stripped from a standalone install) or the project's own
  /// libraries. So we merge the two: the project's resolution, plus the
  /// sandbox packages the CLI provides. If the project has no package config
  /// (e.g. `pub get` was never run), fall back to the CLI's config unchanged.
  Future<Uri> _buildPackageConfig() async {
    final cliUri = await packageConfigUri;
    final projectUri = _findProjectPackageConfig(Directory.current);
    if (projectUri == null) return cliUri;
    return mergePackageConfigs(
      project: projectUri,
      cli: cliUri,
      out: File(p.join(_tempDir.path, 'package_config.json')),
    );
  }

  /// Walks up from [start] looking for a `.dart_tool/package_config.json`,
  /// returning its URI, or `null` if none exists up to the filesystem root.
  static Uri? _findProjectPackageConfig(Directory start) {
    for (var dir = start.absolute; ;) {
      final candidate = File(
        p.join(dir.path, '.dart_tool', 'package_config.json'),
      );
      if (candidate.existsSync()) return candidate.uri;
      final parent = dir.parent;
      if (parent.path == dir.path) return null; // reached the root
      dir = parent;
    }
  }

  /// Writes the generated sandbox bootstrap for [path] to a temp file and
  /// returns its URI.
  Future<Uri> _bootstrapFile(String path, Metadata suiteMetadata) async {
    final file = File(
      p.join(_tempDir.path, p.setExtension(path, '.sandbox.isolate.dart')),
    );
    final source = generateBootstrap(
      config: _config,
      testUri: await absoluteUri(path),
      languageVersionComment:
          suiteMetadata.languageVersionComment ??
          await rootPackageLanguageVersionComment,
    );
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(source);
    return file.uri;
  }

  @override
  Future<void> close() => _closeMemo.runOnce(() async {
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });
}
