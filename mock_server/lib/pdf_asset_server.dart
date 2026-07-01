import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Flutter アプリと同一プロセスで `127.0.0.1:8765` に PDF を配信するアプリ内 HTTP サーバー。
///
/// `start()` に渡したキャッシュを shelf で HTTP GET として返す。
/// ホットリスタートによるポート競合を防ぐため、呼び出し元でトップレベル・シングルトンとして保持すること。
class PdfAssetServer {
  /// HTTP サーバーのポート番号。
  static const int port = 8765;
  HttpServer? _server;

  /// [pdfCache]（ファイル名 → バイト列）を配信するサーバーを `127.0.0.1:[port]` で起動する。
  ///
  /// 既に起動中の場合はスキップ。ポート競合時は [stderr] にログして静かに続行する。
  Future<void> start(Map<String, Uint8List> pdfCache) async {
    if (_server != null) return;

    try {
      _server = await io.serve(
        _handler(pdfCache),
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
    } on SocketException catch (e) {
      stderr.writeln('PdfAssetServer: port $port bind failed: $e');
    }
  }

  /// `pathSegments.last`・raw path・パーセントデコード値を複数試行してキャッシュを引く。
  ///
  /// Dio が送るエンコード済みパス（`%E5%8F%B7.pdf`）と Flutter assets の生文字列を突合するため。
  Uint8List? _findPdfBytes(Map<String, Uint8List> cache, Request request) {
    final candidates = <String>{};

    if (request.url.pathSegments.isNotEmpty) {
      candidates.add(request.url.pathSegments.last);
    } else if (request.url.path.isNotEmpty) {
      candidates.add(request.url.path);
    }

    if (request.requestedUri.pathSegments.isNotEmpty) {
      candidates.add(request.requestedUri.pathSegments.last);
    }

    for (final value in candidates.toList()) {
      if (!value.contains('%')) continue;
      try {
        candidates.add(Uri.decodeComponent(value));
      } on FormatException {
        // `%` を含む非正規なパスでも元値で照合を継続する。
      }
    }

    for (final key in candidates) {
      final bytes = cache[key];
      if (bytes != null) {
        return bytes;
      }
    }

    return null;
  }

  Handler _handler(Map<String, Uint8List> cache) => (Request request) {
    final bytes = _findPdfBytes(cache, request);
    if (bytes == null) {
      final path = request.requestedUri.path;
      return Response.notFound('Not found: $path');
    }

    return Response.ok(
      bytes,
      headers: {
        HttpHeaders.contentTypeHeader: 'application/pdf',
        HttpHeaders.contentLengthHeader: bytes.length.toString(),
      },
    );
  };

  /// サーバーを停止してポートを解放する。
  Future<void> shutdown() async {
    await _server?.close(force: true);
    _server = null;
  }
}
