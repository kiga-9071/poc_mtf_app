import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../controllers/source_mode_controller.dart';
import '../../entities/pdf_content.dart';
import '../../l10n.dart';

/// テキスト情報を中心としたリスト表示用のカードウィジェット。
/// カテゴリーバッジ・説明文・ダウンロード進捗・削除ボタンなど詳細情報を表示する。
class ContentListCard extends HookConsumerWidget {
  const ContentListCard({
    super.key,
    required this.content,
    required this.langCode,
  });

  /// 表示するコンテンツの情報
  final PdfContent content;

  /// 現在の表示言語コード（ファイル保存パスの生成に使用）
  final String langCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final sourceMode = ref.watch(sourceModeProvider);

    final isDownloading = useState(false);
    final progress = useState(0.0);
    // ダウンロードごとに新しいトークンを生成するため ValueNotifier で保持する。
    // useMemoized では一度キャンセルしたトークンが使い回されてサイレント失敗するため使わない。
    final cancelToken = useState(CancelToken());
    final isDownloaded = useState(false);
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
      final path = buildSavePath(dirSnapshot.data!, content, langCode);
      cancelToken.value = CancelToken();
      isDownloading.value = true;
      progress.value = 0;

      // ローカルモード: アセットからコピー
      if (sourceMode == SourceMode.local) {
        try {
          final data = await rootBundle.load(content.assetPath);
          await File(path).writeAsBytes(data.buffer.asUint8List());
          if (context.mounted) {
            isDownloading.value = false;
            if (dirSnapshot.data != null) checkDownloadStatus(dirSnapshot.data!);
            context.go('/viewer', extra: path);
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.errorMsg('$e'))),
            );
            isDownloading.value = false;
            progress.value = 0;
          }
        }
        return;
      }

      // サーバーモード: Dio でダウンロード
      final token = cancelToken.value;
      try {
        final dio = Dio();
        await dio.download(
          content.url,
          path,
          cancelToken: token,
          onReceiveProgress: (received, total) {
            if (!context.mounted) return;
            if (total > 0) progress.value = received / total;
          },
        );
        if (context.mounted) {
          isDownloading.value = false;
          if (dirSnapshot.data != null) checkDownloadStatus(dirSnapshot.data!);
          context.go('/viewer', extra: path);
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) return;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.downloadFailed(e.message ?? ''))),
          );
          isDownloading.value = false;
          progress.value = 0;
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorMsg('$e'))),
          );
          isDownloading.value = false;
          progress.value = 0;
        }
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
      if (await file.exists()) await file.delete();
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // カテゴリーバッジ
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(content.category,
                          style: const TextStyle(fontSize: 11)),
                    ),
                    // 保存済みバッジ（ダウンロード済みの場合のみ）
                    if (downloaded) ...[
                      const SizedBox(height: 4),
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
                    ],
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    content.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (downloaded)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: l10n.delete,
                    onPressed: deleteFile,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              content.description,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                    onPressed: () => cancelToken.value.cancel(),
                    child: Text(l10n.cancel,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ] else if (downloaded)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: Text(l10n.open),
                  onPressed: path != null
                      ? () => context.go('/viewer', extra: path)
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
