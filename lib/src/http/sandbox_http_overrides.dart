/// The [HttpOverrides] interception layer.
///
/// `IOOverrides` only hooks `Socket.connect` / `Socket.startConnect` /
/// `ServerSocket.bind`. Plain `http://` requests go through `Socket.startConnect`
/// and are gated by the sandbox, but `https://` uses `SecureSocket` (→
/// `RawSocket`), which `IOOverrides` cannot intercept — so the network gate
/// would miss HTTPS. Installing a [SandboxHttpOverrides] closes that gap: every
/// `HttpClient` created inside the sandbox is wrapped so each request is checked
/// against the policy's `allowNetwork`, regardless of scheme.
library;

import 'dart:io';

import '../context.dart';
import '../errors.dart';
import '../events.dart';

/// An [HttpOverrides] that wraps every `HttpClient` created inside the sandbox
/// with a [_SandboxHttpClient], so HTTP **and HTTPS** requests are gated by the
/// sandbox network policy.
base class SandboxHttpOverrides extends HttpOverrides {
  /// The sandbox this override set serves.
  final SandboxContext context;

  SandboxHttpOverrides(this.context);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _SandboxHttpClient(this.context, super.createHttpClient(context));
}

/// Delegates to a real [HttpClient] but routes every request through the sandbox
/// network gate first. Configuration and lifecycle members pass straight
/// through.
class _SandboxHttpClient implements HttpClient {
  final SandboxContext _context;
  final HttpClient _inner;

  _SandboxHttpClient(this._context, this._inner);

  /// Mirrors the socket-level gate: emits an access event and throws when
  /// network access is disabled, otherwise records the allowed attempt.
  void _guard(String host, int port) {
    final target = '$host:$port';
    if (!_context.policy.allowNetwork) {
      _context.emit(
        SandboxAccessEvent(
          type: SandboxAccessType.network,
          target: target,
          allowed: false,
          reason: 'network access is disabled by the sandbox policy',
        ),
      );
      throw SandboxViolationError.network(target);
    }
    _context.emit(
      SandboxAccessEvent(
        type: SandboxAccessType.network,
        target: target,
        allowed: true,
      ),
    );
  }

  // --- Request entry points (gated) --------------------------------------

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) {
    _guard(host, port);
    return _inner.open(method, host, port, path);
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    _guard(url.host, url.port);
    return _inner.openUrl(method, url);
  }

  @override
  Future<HttpClientRequest> get(String host, int port, String path) {
    _guard(host, port);
    return _inner.get(host, port, path);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    _guard(url.host, url.port);
    return _inner.getUrl(url);
  }

  @override
  Future<HttpClientRequest> post(String host, int port, String path) {
    _guard(host, port);
    return _inner.post(host, port, path);
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    _guard(url.host, url.port);
    return _inner.postUrl(url);
  }

  @override
  Future<HttpClientRequest> put(String host, int port, String path) {
    _guard(host, port);
    return _inner.put(host, port, path);
  }

  @override
  Future<HttpClientRequest> putUrl(Uri url) {
    _guard(url.host, url.port);
    return _inner.putUrl(url);
  }

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) {
    _guard(host, port);
    return _inner.delete(host, port, path);
  }

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) {
    _guard(url.host, url.port);
    return _inner.deleteUrl(url);
  }

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) {
    _guard(host, port);
    return _inner.patch(host, port, path);
  }

  @override
  Future<HttpClientRequest> patchUrl(Uri url) {
    _guard(url.host, url.port);
    return _inner.patchUrl(url);
  }

  @override
  Future<HttpClientRequest> head(String host, int port, String path) {
    _guard(host, port);
    return _inner.head(host, port, path);
  }

  @override
  Future<HttpClientRequest> headUrl(Uri url) {
    _guard(url.host, url.port);
    return _inner.headUrl(url);
  }

  // --- Configuration & lifecycle (pass-through) --------------------------

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _inner.badCertificateCallback = callback;

  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
