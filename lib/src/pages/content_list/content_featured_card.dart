import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../entities/pdf_content.dart';
import '../../entities/viewer_args.dart';
import '../../l10n.dart';

/// 機内誌タブ用の大型フィーチャードカード。
/// 表紙画像を画面中央に大きく表示し、タイトル・説明・アクションボタンを並べる。
class ContentFeaturedCard extends HookConsumerWidget {
  const ContentFeaturedCard({
    super.key,
    required this.content,
    required this.langCode,
    required this.isAvailable,
  });

  final PdfContent content;
  final String langCode;
  final bool isAvailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isDownloading = useState(false);
    final progress = useState(0.0);
    final currentTaskId = useState<String?>(null);
    final isDownloaded = useState(false);
    final savedPath = useState<String?>(null);

    void checkDownloadStatus(Directory dir) {
      final path = buildSavePath(dir, content, langCode);
      final file = File(path);
      if (file.existsSync()) {
        isDownloaded.value = true;
        savedPath.value = path;
      } else {
        isDownloaded.value = false;
        savedPath.value = null;
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
      isDownloading.value = true;
      progress.value = 0;

      final taskId = '${content.id}_$langCode';
      currentTaskId.value = taskId;
      try {
        final result = await FileDownloader().download(
          DownloadTask(
            taskId: taskId,
            url: Uri.encodeFull(content.url),
            filename: path.split('/').last,
            directory: '',
            baseDirectory: BaseDirectory.applicationDocuments,
            updates: Updates.statusAndProgress,
          ),
          onProgress: (prog) {
            if (!context.mounted) return;
            progress.value = prog;
          },
        );
        if (!context.mounted) return;
        currentTaskId.value = null;
        switch (result.status) {
          case TaskStatus.complete:
            isDownloading.value = false;
            if (dirSnapshot.data != null) checkDownloadStatus(dirSnapshot.data!);
            context.go('/viewer',
                extra: ViewerArgs(
                    filePath: path,
                    preventCapture: content.preventCapture));
          case TaskStatus.canceled:
            isDownloading.value = false;
            progress.value = 0;
          default:
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      l10n.downloadFailed(result.exception?.description ?? ''))),
            );
            isDownloading.value = false;
            progress.value = 0;
        }
      } catch (e) {
        if (!context.mounted) return;
        currentTaskId.value = null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorMsg('$e'))),
        );
        isDownloading.value = false;
        progress.value = 0;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.deletedMsg(content.title))),
        );
      }
    }

    final downloaded = isDownloaded.value;
    final path = savedPath.value;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 表紙画像の幅: 画面幅の 65%、最大 320px
            final coverWidth =
                (MediaQuery.of(context).size.width * 0.65).clamp(0.0, 320.0);
            // A4縦比率 (1:√2)
            final coverHeight = coverWidth * 1.414;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 表紙画像 ──────────────────────────────────────────────────
                SizedBox(
                  width: coverWidth,
                  height: coverHeight,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(4, 8),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            content.previewImageAsset,
                            width: coverWidth,
                            height: coverHeight,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, _, __) => Container(
                              width: coverWidth,
                              height: coverHeight,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF2C2C2C)
                                    : const Color(0xFFF0F0F0),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.picture_as_pdf,
                                size: 80,
                                color: isDark
                                    ? Colors.grey[600]
                                    : Colors.grey[400],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ダウンロード中オーバーレイ
                      if (isDownloading.value)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.55),
                            child: SizedBox(
                              width: coverWidth,
                              height: coverHeight,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: CircularProgressIndicator(
                                      value: progress.value > 0
                                          ? progress.value
                                          : null,
                                      color: Colors.white,
                                      strokeWidth: 4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '${(progress.value * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── カテゴリーバッジ ──────────────────────────────────────────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    content.category,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),

                const SizedBox(height: 12),

                // ── タイトル ──────────────────────────────────────────────────
                Text(
                  content.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 8),

                // ── 説明文 ────────────────────────────────────────────────────
                Text(
                  content.description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black54),
                ),

                const SizedBox(height: 24),

                // ── アクションボタン ──────────────────────────────────────────
                SizedBox(
                  width: coverWidth,
                  child: isDownloading.value
                      ? Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress.value,
                                minHeight: 8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                if (currentTaskId.value != null) {
                                  FileDownloader().cancelTaskWithId(
                                      currentTaskId.value!);
                                }
                              },
                              icon: const Icon(Icons.cancel,
                                  color: Colors.red, size: 18),
                              label: Text(l10n.cancel,
                                  style: const TextStyle(color: Colors.red)),
                            ),
                          ],
                        )
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            textStyle: const TextStyle(fontSize: 15),
                          ),
                          onPressed: !isAvailable
                              ? null
                              : downloaded
                                  ? (path != null
                                      ? () => context.go('/viewer',
                                          extra: ViewerArgs(
                                              filePath: path,
                                              preventCapture:
                                                  content.preventCapture))
                                      : null)
                                  : (dirSnapshot.hasData ? download : null),
                          child: Text(!isAvailable
                              ? l10n.contentUnavailableButton
                              : downloaded
                                  ? l10n.open
                                  : l10n.downloadAndSave),
                        ),
                ),

                // ダウンロード済みの場合は削除ボタンも表示
                if (downloaded && !isDownloading.value) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: deleteFile,
                    icon: Icon(Icons.delete_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.error),
                    label: Text(
                      l10n.deleteFile,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
