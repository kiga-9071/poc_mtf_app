import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/pdf_content.dart';
import 'pdf_preview_cache.dart';

/// マスターJSONの lastUpdatedAt とローカルDL日時を比較し、
/// 差分があるコンテンツをバックグラウンドで再ダウンロードするサービス。
class ContentUpdateService {
  ContentUpdateService._();

  static const _keyPrefix = 'content_dl_at_';

  static String _key(String contentId, String langCode) =>
      '$_keyPrefix${contentId}_$langCode';

  /// DL完了時に呼び出す。SharedPreferences に現在時刻を保存する。
  static Future<void> saveDownloadTimestamp(
      String contentId, String langCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(contentId, langCode),
      DateTime.now().toIso8601String(),
    );
  }

  /// アプリ起動・復帰時に呼び出す。
  /// ダウンロード済みコンテンツの lastUpdatedAt を保存済みDL日時と比較し、
  /// マスターが新しい場合はバックグラウンドで差し替えダウンロードを実行する。
  static Future<void> checkAndUpdateAll(
    List<PdfContent> contents,
    String langCode,
    Directory dir,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    for (final content in contents) {
      if (content.isWebContent) continue;
      if (content.lastUpdatedAt == null) continue;

      final destPath = buildSavePath(dir, content, langCode);
      if (!File(destPath).existsSync()) continue;

      final storedStr = prefs.getString(_key(content.id, langCode));
      final downloadedAt =
          storedStr != null ? DateTime.tryParse(storedStr) : null;

      // downloadedAt が null（旧バージョンからの移行）または
      // lastUpdatedAt が downloadedAt より新しければ差し替え
      if (downloadedAt == null ||
          content.lastUpdatedAt!.isAfter(downloadedAt)) {
        debugPrint(
          '[ContentUpdate] 更新検出: ${content.title} '
          '(master=${content.lastUpdatedAt?.toIso8601String()}, '
          'local=${downloadedAt?.toIso8601String() ?? "未記録"})',
        );
        // ignore: unawaited_futures
        _redownloadSilently(content, langCode, destPath, prefs);
      }
    }
  }

  static Future<void> _redownloadSilently(
    PdfContent content,
    String langCode,
    String destPath,
    SharedPreferences prefs,
  ) async {
    final tempPath = '$destPath.update_tmp';
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 10),
      ));

      final isLocal = content.url.startsWith('http://127.0.0.1');
      if (isLocal) {
        try {
          await dio.download(Uri.encodeFull(content.url), tempPath);
        } catch (_) {
          // モックサーバー未起動時はバンドルアセットにフォールバック
          final filename = content.url.split('/').last;
          final data = await rootBundle
              .load('packages/mock_server/assets/pdfs/$filename');
          await File(tempPath).writeAsBytes(data.buffer.asUint8List());
        }
      } else {
        await dio.download(Uri.encodeFull(content.url), tempPath);
      }

      // 旧ファイルを削除してから差し替え
      final dest = File(destPath);
      if (await dest.exists()) await dest.delete();
      await File(tempPath).rename(destPath);

      // サムネイルキャッシュを無効化（次回 warmUp で再生成される）
      _clearThumbnailCache(destPath);

      // DLタイムスタンプを更新
      await prefs.setString(
        _key(content.id, langCode),
        DateTime.now().toIso8601String(),
      );

      debugPrint('[ContentUpdate] 差し替え完了: ${content.title}');
    } catch (e) {
      debugPrint('[ContentUpdate] 差し替え失敗: ${content.title} / $e');
      try {
        await File(tempPath).delete();
      } catch (_) {}
    }
  }

  static void _clearThumbnailCache(String pdfPath) {
    for (var i = 0; i < 20; i++) {
      try {
        File(PdfPreviewCache.cachePath(pdfPath, i)).deleteSync();
      } catch (_) {}
    }
  }
}
