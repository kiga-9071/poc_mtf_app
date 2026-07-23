import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Flutter アプリと同一プロセスで `127.0.0.1:8765` にコンテンツを配信するアプリ内 HTTP サーバー。
///
/// **起動時に PDF をメモリに展開しない**。
/// PDF は最初にリクエストされたとき assets から一時ディレクトリへ展開し、
/// 以降はファイルシステムから直接配信する（Range Request 対応）。
/// これにより大容量 PDF がある場合でもアプリ起動が遅くならない。
class PdfAssetServer {
  static const int port = 8765;
  HttpServer? _server;

  /// 小サイズのインメモリコンテンツ（contents.json 等）
  final Map<String, Uint8List> _memCache = {};

  /// 展開済みの PDF ファイル（ファイル名 → File）
  final Map<String, File> _fileCache = {};

  /// 展開中の Future（重複展開を防ぐ）
  final Map<String, Future<File?>> _extracting = {};

  /// PDF を展開する一時ディレクトリ
  Directory? _tempDir;

  /// [memCache]（contents.json 等の小ファイル）だけをメモリに保持してサーバーを起動する。
  /// PDF は最初のリクエスト時にオンデマンドで assets から展開する。
  Future<void> start(Map<String, Uint8List> memCache) async {
    if (_server != null) return;
    _memCache.addAll(memCache);
    _tempDir = Directory('${Directory.systemTemp.path}/pdf_asset_server');
    await _tempDir!.create(recursive: true);

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        _server = await io.serve(
          _handler,
          InternetAddress.loopbackIPv4,
          port,
          shared: true,
        );
        debugPrint('PdfAssetServer: listening on 127.0.0.1:$port');
        return;
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 98 && attempt < 2) {
          debugPrint(
            'PdfAssetServer: port $port busy (attempt ${attempt + 1}), retrying...',
          );
          await Future<void>.delayed(const Duration(milliseconds: 500));
        } else {
          debugPrint('PdfAssetServer: port $port bind failed: $e');
          return;
        }
      } catch (e) {
        debugPrint('PdfAssetServer: port $port bind failed: $e');
        return;
      }
    }
  }

  String _resolveFilename(Request request) {
    String name = request.url.pathSegments.isNotEmpty
        ? request.url.pathSegments.last
        : request.url.path;
    if (name.contains('%')) {
      try {
        name = Uri.decodeComponent(name);
      } on FormatException {
        // パーセントエンコードが壊れている場合は元の値を使う
      }
    }
    return name;
  }

  /// assets からファイルを一時ディレクトリへ展開する（同一ファイルの重複展開を防ぐ）。
  Future<File?> _extractAsset(String filename) {
    if (_fileCache.containsKey(filename)) {
      return Future.value(_fileCache[filename]);
    }
    // putIfAbsent は同期的なので複数リクエストが同時に来ても同じ Future を返す
    return _extracting.putIfAbsent(filename, () => _doExtract(filename));
  }

  Future<File?> _doExtract(String filename) async {
    try {
      final file = File('${_tempDir!.path}/$filename');
      if (await file.exists()) {
        _fileCache[filename] = file;
        _extracting.remove(filename);
        debugPrint('PdfAssetServer: cache hit for "$filename"');
        return file;
      }

      debugPrint('PdfAssetServer: extracting "$filename" from assets…');
      final data = await rootBundle
          .load('packages/mock_server/assets/pdfs/$filename');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      _fileCache[filename] = file;
      _extracting.remove(filename);
      final mb = (data.lengthInBytes / 1024 / 1024).toStringAsFixed(1);
      debugPrint('PdfAssetServer: extracted "$filename" ($mb MB)');
      return file;
    } catch (e) {
      _extracting.remove(filename);
      debugPrint('PdfAssetServer: failed to extract "$filename": $e');
      return null;
    }
  }

  Future<Response> _handler(Request request) async {
    final filename = _resolveFilename(request);
    if (filename.isEmpty) return Response.notFound('Not found');

    // インメモリコンテンツ（contents.json 等）
    final mem = _memCache[filename];
    if (mem != null) {
      return _buildMemResponse(request, mem, _mimeType(filename));
    }

    // PDF: assets から展開してファイル配信
    final file = await _extractAsset(filename);
    if (file == null) {
      return Response.notFound('Not found: $filename');
    }
    return _buildFileResponse(request, file);
  }

  String _mimeType(String filename) {
    if (filename.endsWith('.pdf')) return 'application/pdf';
    if (filename.endsWith('.json')) return 'application/json; charset=utf-8';
    return 'application/octet-stream';
  }

  /// インメモリバイト列を Range Request 対応で返す。
  Response _buildMemResponse(
      Request request, Uint8List bytes, String mime) {
    final size = bytes.length;
    final base = {
      HttpHeaders.contentTypeHeader: mime,
      'Accept-Ranges': 'bytes',
    };
    final range = _parseRange(request.headers[HttpHeaders.rangeHeader], size);
    if (range == null) {
      return Response.ok(
        bytes,
        headers: {...base, HttpHeaders.contentLengthHeader: '$size'},
      );
    }
    final (s, e) = range;
    return Response(
      206,
      body: bytes.sublist(s, e + 1),
      headers: {
        ...base,
        HttpHeaders.contentLengthHeader: '${e - s + 1}',
        'Content-Range': 'bytes $s-$e/$size',
      },
    );
  }

  /// ファイルシステム上の PDF を Range Request 対応でストリーム配信する。
  Future<Response> _buildFileResponse(Request request, File file) async {
    final size = await file.length();
    final mime = _mimeType(file.path.split('/').last);
    final base = {
      HttpHeaders.contentTypeHeader: mime,
      'Accept-Ranges': 'bytes',
    };
    final range = _parseRange(request.headers[HttpHeaders.rangeHeader], size);
    if (range == null) {
      return Response.ok(
        file.openRead(),
        headers: {...base, HttpHeaders.contentLengthHeader: '$size'},
      );
    }
    final (s, e) = range;
    return Response(
      206,
      body: file.openRead(s, e + 1),
      headers: {
        ...base,
        HttpHeaders.contentLengthHeader: '${e - s + 1}',
        'Content-Range': 'bytes $s-$e/$size',
      },
    );
  }

  /// `Range: bytes=start-end` ヘッダーを解析して (start, end) を返す。
  /// 不正・範囲外・ヘッダーなしの場合は null を返す。
  (int, int)? _parseRange(String? header, int size) {
    if (header == null) return null;
    final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(header);
    if (m == null) return null;
    final s = int.parse(m.group(1)!);
    final eStr = m.group(2)!;
    final e = eStr.isEmpty ? size - 1 : int.parse(eStr);
    if (s >= size || e >= size || s > e) return null;
    return (s, e);
  }

  /// [filenames] の PDF を assets からバックグラウンドで一時ディレクトリへ展開する。
  ///
  /// アプリ起動直後にコールすることで、ユーザーが PDF を開く前に
  /// 展開済み状態にしておき初回表示の待ち時間を短縮する。
  /// エラーは無視して続行する（失敗してもオンデマンド展開にフォールバックする）。
  Future<void> warmUp(Iterable<String> filenames) async {
    for (final name in filenames) {
      if (_fileCache.containsKey(name)) continue;
      await _extractAsset(name).catchError((_) => null);
    }
  }

  Future<void> shutdown() async {
    await _server?.close(force: true);
    _server = null;
  }
}
