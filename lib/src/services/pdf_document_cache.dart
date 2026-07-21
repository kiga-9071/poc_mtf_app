import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// ダウンロード済みPDFを事前に Pdfium で開いておくキャッシュ。
///
/// ビューアを開く際に [PdfDocumentRefDirect] 経由で渡すことで、
/// Pdfium のドキュメントオープン待ち（数秒）をゼロにする。
class PdfDocumentCache {
  PdfDocumentCache._();

  static final _cache = <String, PdfDocument>{};
  static final _pending = <String, Future<void>>{};

  /// [filePath] の PDF を Pdfium で事前オープンしてキャッシュする。
  /// 既にキャッシュ済み・ロード中の場合は何もしない（重複オープンを防ぐ）。
  static Future<void> warmUp(String filePath) async {
    if (_cache.containsKey(filePath)) return;
    if (_pending.containsKey(filePath)) {
      await _pending[filePath];
      return;
    }
    final future = _doWarmUp(filePath);
    _pending[filePath] = future;
    try {
      await future;
    } finally {
      _pending.remove(filePath);
    }
  }

  static Future<void> _doWarmUp(String filePath) async {
    try {
      final doc = await PdfDocument.openFile(filePath);
      _cache[filePath] = doc;
      debugPrint('[PdfDocumentCache] warmed up: ${filePath.split('/').last}');
    } catch (e) {
      debugPrint('[PdfDocumentCache] warmUp failed: $filePath: $e');
    }
  }

  /// キャッシュ済みの [PdfDocument] を返す。未キャッシュなら null。
  static PdfDocument? get(String filePath) => _cache[filePath];

  /// キャッシュから除去してドキュメントを破棄する（ファイル削除時に呼ぶ）。
  static void evict(String filePath) {
    _pending.remove(filePath);
    _cache.remove(filePath)?.dispose();
    debugPrint('[PdfDocumentCache] evicted: ${filePath.split('/').last}');
  }
}
