import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../entities/pdf_content.dart';
import '../../entities/viewer_args.dart';
import '../../l10n.dart';
import '../../services/storage_limit_service.dart';
import 'storage_limit_dialog.dart';

/// テキスト情報を中心としたリスト表示用のカードウィジェット。
/// カテゴリーバッジ・説明文・ダウンロード進捗・削除ボタンなど詳細情報を表示する。
class ContentListCard extends HookConsumerWidget {
  const ContentListCard({
    super.key,
    required this.content,
    required this.langCode,
    required this.isAvailable,
  });

  /// 表示するコンテンツの情報
  final PdfContent content;

  /// 現在の表示言語コード（ファイル保存パスの生成に使用）
  final String langCode;

  /// 表示期間内かどうか（false の場合はダウンロード・閲覧を無効化）
  final bool isAvailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);

    final isDownloading = useState(false);
    final progress = useState(0.0);
    final cancelToken = useState<CancelToken?>(null);
    final isDownloaded = useState(false);
    final dio = useMemoized(() => Dio(BaseOptions(connectTimeout: const Duration(seconds: 3))));
    final savedPath = useState<String?>(null);
    final fileSize = useState<int?>(null);

    void checkDownloadStatus(Directory dir) {
      final path = buildSavePath(dir, content, langCode);
      final file = File(path);
      if (file.existsSync()) {
        isDownloaded.value = true;
        savedPath.value = path;
        fileSize.value = file.lengthSync();
      } else {
        isDownloaded.value = false;
        savedPath.value = null;
        fileSize.value = null;
      }
    }

    final dirFuture = useMemoized(getApplicationDocumentsDirectory);
    final dirSnapshot = useFuture(dirFuture);

    useEffect(() {
      if (dirSnapshot.hasData) checkDownloadStatus(dirSnapshot.data!);
      return null;
    }, [dirSnapshot.data]);

    Future<void> download() async {
      if (dirSnapshot.data == null) return;

      // ── 容量上限チェック ──────────────────────────────────────────────────
      final exceeded = await StorageLimitService.checkBeforeDownload();
      if (exceeded != null) {
        if (context.mounted) {
          await showStorageLimitExceededDialog(
            context,
            usage: exceeded.usage,
            limit: exceeded.limit,
          );
        }
        return;
      }

      final path = buildSavePath(dirSnapshot.data!, content, langCode);
      isDownloading.value = true;
      progress.value = 0;

      final token = CancelToken();
      cancelToken.value = token;
      try {
        await dio.download(
          Uri.encodeFull(content.url),
          path,
          cancelToken: token,
          onReceiveProgress: (received, total) {
            if (!context.mounted) return;
            if (total > 0) progress.value = received / total;
          },
        );
        if (!context.mounted) return;
        cancelToken.value = null;
        isDownloading.value = false;
        // ignore: unawaited_futures
        StorageLimitService.recordFile(
            path.split('/').last, File(path).lengthSync(), content.id);
        if (dirSnapshot.data != null) checkDownloadStatus(dirSnapshot.data!);
        context.go('/viewer', extra: ViewerArgs(filePath: path, preventCapture: content.preventCapture));
      } on DioException catch (e) {
        if (!context.mounted) return;
        cancelToken.value = null;
        if (e.type == DioExceptionType.cancel) {
          isDownloading.value = false;
          progress.value = 0;
          return;
        }
        try {
          final filename = content.url.split('/').last;
          final assetData = await rootBundle.load(
            'packages/mock_server/assets/pdfs/$filename',
          );
          if (!context.mounted) return;
          await File(path).writeAsBytes(assetData.buffer.asUint8List());
          if (!context.mounted) return;
          isDownloading.value = false;
          progress.value = 1.0;
          // ignore: unawaited_futures
          StorageLimitService.recordFile(
              path.split('/').last, File(path).lengthSync(), content.id);
          if (dirSnapshot.data != null) checkDownloadStatus(dirSnapshot.data!);
          context.go('/viewer', extra: ViewerArgs(filePath: path, preventCapture: content.preventCapture));
        } catch (fallbackErr) {
          if (!context.mounted) return;
          isDownloading.value = false;
          progress.value = 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.downloadFailed('$fallbackErr'))),
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        cancelToken.value = null;
        isDownloading.value = false;
        progress.value = 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorMsg('$e'))),
        );
      }
    }

    Future<void> deleteFile() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.deleteFile),
          content: Text(l10n.deleteConfirm(content.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final path = savedPath.value;
      if (path == null) return;
      final file = File(path);
      if (await file.exists()) {
        await StorageLimitService.removeFile(path.split('/').last);
        await file.delete();
      }
      if (context.mounted) {
        isDownloaded.value = false;
        savedPath.value = null;
        fileSize.value = null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.deletedMsg(content.title))),
        );
      }
    }

    final downloaded = isDownloaded.value;
    final path = savedPath.value;
    final size = fileSize.value;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // タイトル行（常に全幅・左寄せ）
            Text(
              content.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // バッジ行: カテゴリー・保存済み + 削除ボタン
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      // カテゴリーバッジ
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(content.category,
                            style: const TextStyle(fontSize: 11)),
                      ),
                      // 保存済みバッジ（ダウンロード済みの場合のみ）
                      if (downloaded)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle,
                                  size: 11, color: Colors.green.shade700),
                              const SizedBox(width: 3),
                              Text(
                                '${l10n.saved}${size != null ? '  ${formatFileSize(size)}' : ''}',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green.shade700),
                              ),
                            ],
                          ),
                        ),
                      // 公開期間外バッジ
                      if (!isAvailable)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Text(
                            content.availableTo != null &&
                                    DateTime.now()
                                        .isAfter(content.availableTo!)
                                ? l10n.contentExpired
                                : l10n.contentNotYet,
                            style: TextStyle(
                                fontSize: 10, color: Colors.red.shade700),
                          ),
                        ),
                    ],
                  ),
                ),
                // 削除ボタン（ダウンロード済みの場合のみ）
                if (downloaded)
                  GestureDetector(
                    onTap: deleteFile,
                    child: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              content.description,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            if (isDownloading.value) ...[
              LinearProgressIndicator(value: progress.value),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${l10n.downloading} ${(progress.value * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                  TextButton(
                    onPressed: () => cancelToken.value?.cancel(),
                    child: Text(l10n.cancel,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ] else if (!isAvailable)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.lock_outline),
                  label: Text(l10n.contentUnavailableButton),
                  onPressed: null,
                ),
              )
            else if (downloaded)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: Text(l10n.open),
                  onPressed: path != null
                      ? () => context.go('/viewer',
                          extra: ViewerArgs(
                              filePath: path,
                              preventCapture: content.preventCapture))
                      : null,
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: Text(l10n.downloadAndSave),
                  onPressed: dirSnapshot.hasData ? download : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
