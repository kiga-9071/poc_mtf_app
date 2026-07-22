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

  /// ストリップサムネイル用のキャッシュパス（プレビューとは別サイズ）。
  /// プレフィックスに数字を含めると旧形式（.s{n}）と衝突するため、
  /// 文字のみのプレフィックス `.strip` を使用する。
  ///   旧 .s{n}  → .s30.jpg が新 .s3{n} の n=0 と一致（衝突！）
  ///   新 .strip{n} → いかなる旧形式とも一致しない（安全）
  static String stripCachePath(String pdfPath, int pageIndex) =>
      '$pdfPath.strip$pageIndex.jpg';

  /// ネイティブサムネイル API 経由で JPEG バイト列を取得する。
  /// [width] を省略すると全幅プレビュー用の 400px で生成する。
  /// 失敗した場合は null を返す。
  static Future<Uint8List?> fetchNativeThumbnail(
      String pdfPath, int pageIndex, {double? width}) async {
    try {
      return await _channel.invokeMethod<Uint8List>('getThumbnail', {
        'path': pdfPath,
        'pageIndex': pageIndex,
        'width': (width ?? _previewWidth).toDouble(),
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

  /// ストリップサムネイルを全ページ分バックグラウンドで生成してディスクにキャッシュする。
  ///
  /// PDF ビューアが開いた直後に fire-and-forget で呼ぶことで、ユーザーがサムネイルストリップを
  /// スクロールする頃にはほぼ全ページがディスクキャッシュ済みとなり即時表示が可能になる。
  ///
  /// - iOS: PDFKit.PDFPage.thumbnail を使用（キャッシュ済み PDFDocument で高速）
  /// - Android: ネイティブ API 未実装のため何もしない（null を返すだけで安全）
  /// - 既にディスクキャッシュが存在するページはスキップする
  static Future<void> preWarmStrip(String pdfPath, int pageCount) async {
    for (int i = 0; i < pageCount; i++) {
      final path = stripCachePath(pdfPath, i);
      try {
        if (await File(path).exists()) continue;
      } catch (_) {}

      final bytes =
          await fetchNativeThumbnail(pdfPath, i, width: _stripThumbnailWidth);
      if (bytes == null) return; // ネイティブ API 未対応環境（Android 等）は即終了

      try {
        await File(path).writeAsBytes(bytes);
      } catch (_) {}
    }
    debugPrint(
        '[PdfPreviewCache] strip pre-warm done: ${pdfPath.split('/').last} ($pageCount pages)');
  }

  // ストリップサムネイルの物理ピクセル幅（@2x 相当）
  static const double _stripThumbnailWidth = 140.0;
}
