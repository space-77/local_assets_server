import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:mime/mime.dart';

import 'package:flutter/services.dart';

abstract class Logger {
  void logOk(String path, String contentType);
  void logNotFound(String path, String contentType);
}

// Pass an instance of DebugLogger to view logs only in dev builds
class DebugLogger implements Logger {
  const DebugLogger();
  _log(String path, String contentType, int code) {
    if (!kReleaseMode) {
      debugPrint('GET $path – $code; mime: $contentType');
    }
  }

  logOk(String path, String contentType) {
    _log(path, contentType, 200);
  }

  logNotFound(String path, String contentType) {
    _log(path, contentType, 404);
  }
}

// Default logger which does nothing. Use DebugLogger if you want to view access logs in console
class SilentLogger implements Logger {
  const SilentLogger();

  @override
  logNotFound(String path, String contentType) {}

  @override
  logOk(String path, String contentType) {}
}

abstract class CustomRequest {
  bool test(String path);

  Future<ByteData> loadAsset(String path, HttpRequest request, String? mime);
}

class LocalAssetsServer {
  /// Server address
  final InternetAddress address;

  /// Optional server port (note: might be already taken)
  /// Defaults to 0 (binds server to a random free port)
  final int port;

  /// Assets base path
  final String assetsBasePath;

  final Directory? _rootDir;
  HttpServer? _server;

  final String index;

  final String cacheValue;

  final Logger logger;

  final CustomRequest? customRequest;

  LocalAssetsServer({
    required this.address,
    required this.assetsBasePath,

    // Pass this argument if you want your assets to be served from app directory, not from app bundle
    Directory? rootDir,
    // TCP port server will be listening on. Will choose an available port automatically if no port was passed
    this.port = 0,
    this.index = 'index.html',
    this.cacheValue = 'max-age=3600, must-revalidate',
    this.logger = const SilentLogger(),
    this.customRequest,
  }) : this._rootDir = rootDir;

  /// Actual port server is listening on
  int? get boundPort => _server?.port;

  /// Starts server
  Future<InternetAddress> serve({bool shared = false}) async {
    final s = await HttpServer.bind(this.address, this.port, shared: shared);
    s.listen(_handleReq);

    _server = s;

    return s.address;
  }

  Future<void> stop() async {
    await _server?.close();
  }

  _handleReq(HttpRequest request) async {
    String path = request.requestedUri.path.replaceFirst('/', '');

    if (path == '') path = index;

    final name = basename(path);
    final mime = lookupMimeType(name);

    try {
      late final ByteData data;

      if (customRequest?.test(path) ?? false) {
        data = await customRequest!.loadAsset(path, request, mime);
      } else {
        data = await _loadAsset(path);
        request.response.headers.set(HttpHeaders.cacheControlHeader, cacheValue);
      }

      request.response.headers.add('Content-Type', '$mime; charset=utf-8');
      request.response.add(data.buffer.asUint8List());

      request.response.close();
      logger.logOk(path, mime.toString());
    } catch (err) {
      request.response.statusCode = 404;
      request.response.close();
      logger.logNotFound(path, mime.toString());
    }
  }

  Future<ByteData> _loadAsset(String path) async {
    if (_rootDir == null) {
      ByteData data = await rootBundle.load(join(assetsBasePath, path));
      return data;
    }

    print(join(_rootDir!.path, path));
    final f = File(join(_rootDir!.path, path));
    return (await f.readAsBytes()).buffer.asByteData();
  }
}
