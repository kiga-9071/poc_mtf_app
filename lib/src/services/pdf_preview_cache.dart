import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// PDFの低解像度プレビュー画像をディスクにキャッシュするユーティリティ。
///
/// ## 取得優先度
/// 1. ディスクキャッシュ（2回目以降は < 100ms）
/// 2. ネイティブサムネイル API（iOS: PDFPage.thumbnail / Android: PdfRenderer）
///    → 組み込みサムネイルがあれば < 200ms、なくても < 1s
///
/// ## キャッシュファイル
/// `{pdfPath}.p{pageIndex}.jpg`（0始まりページ番号）
class PdfPreviewCache {
  PdfPreviewCache._();

  static const _channel = MethodChannel('app.pdf.thumbnail');
  static const int _previewWidth = 400;

  /// ページキャッシュのファイルパスを返す。
  static String cachePath(String pdfPath, int pageIndex) =>
      '$pdfPath.p$pageIndex.jpg';

  /// ネイティブサムネイル API 経由で JPEG バイト列を取得する。
  /// 失敗した場合は null を返す。
  static Future<Uint8List?> fetchNativeThumbnail(
      String pdfPath, int pageIndex) async {
    try {
      return await _channel.invokeMethod<Uint8List>('getThumbnail', {
        'path': pdfPath,
        'pageIndex': pageIndex,
        'width': _previewWidth.toDouble(),
      });
    } catch (_) {
      return null;
    }
  }

  /// [pdfPath] の page 0 プレビューをバックグラウンドで生成してディスクに保存する。
  /// キャッシュが既に存在する場合は何もしない。
  /// fire-and-forget（await しない）で呼ぶ想定。
  static Future<void> warmUp(String pdfPath) async {
    final cache = File(cachePath(pdfPath, 0));
    try {
      if (await cache.exists()) return;
    } catch (_) {
      return;
    }

    // ネイティブサムネイル API（最速）
    // pdfrx (PdfDocument.openFile) はここでは使わない。
    // viewer 側でも Pdfium が開くため競合し、初期表示が倍の時間になる。
    final nativeBytes = await fetchNativeThumbnail(pdfPath, 0);
    if (nativeBytes != null) {
      try {
        await cache.writeAsBytes(nativeBytes);
        debugPrint(
            '[PdfPreviewCache] cached (native) page 0: ${pdfPath.split('/').last}');
      } catch (_) {}
    }
  }
}
