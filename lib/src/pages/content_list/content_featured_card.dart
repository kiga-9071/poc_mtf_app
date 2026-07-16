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

/// 機内誌タブ用の大型フィーチャードカード。
/// 表紙画像を画面中央に大きく表示し、タイトル・説明・アクションボタンを並べる。
class ContentFeaturedCard extends HookConsumerWidget {
  const ContentFeaturedCard({
    super.key,
    required this.content,
    required this.langCode,
    required this.isAvailable,
    this.inline = false,
  });

  final PdfContent content;
  final String langCode;
  final bool isAvailable;
  final bool inline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isDownloading = useState(false);
    final progress = useState(0.0);
    final cancelToken = useState<CancelToken?>(null);
    final isDownloaded = useState(false);
    final savedPath = useState<String?>(null);
    final dio = useMemoized(() => Dio(BaseOptions(connectTimeout: const Duration(seconds: 3))));

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
        context.go('/viewer',
            extra: ViewerArgs(
                filePath: path,
                preventCapture: content.preventCapture));
      } on DioException catch (e) {
        if (!context.mounted) return;
        cancelToken.value = null;
        if (e.type == DioExceptionType.cancel) {
          isDownloading.value = false;
          progress.value = 0;
          return;
        }
        // サーバー接続失敗時はバンドルアセットからフォールバック
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
          context.go('/viewer',
              extra: ViewerArgs(
                  filePath: path,
                  preventCapture: content.preventCapture));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.deletedMsg(content.title))),
        );
      }
    }

    final downloaded = isDownloaded.value;
    final path = savedPath.value;

    // ── inline モード（Figma スタイル：白カード内に埋め込み） ──────────────
    if (inline) {
      const coverWidth = 153.0;
      const coverHeight = 217.0;
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // セクションヘッダー
            const Text(
              '最新号を読む',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // 表紙画像（中央揃え）
            Center(
              child: SizedBox(
                width: coverWidth,
                height: coverHeight,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset(
                        'assets/skyward_cover.png',
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
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(Icons.picture_as_pdf,
                              size: 60,
                              color: isDark
                                  ? Colors.grey[600]
                                  : Colors.grey[400]),
                        ),
                      ),
                    ),
                    if (isDownloading.value)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.55),
                          child: SizedBox(
                            width: coverWidth,
                            height: coverHeight,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: CircularProgressIndicator(
                                    value: progress.value > 0
                                        ? progress.value
                                        : null,
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${(progress.value * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
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
            ),

            const SizedBox(height: 10),

            // タイトル
            Text(
              content.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                  color: isDark ? Colors.white : Colors.black),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 16),

            // ダウンロード / 開くボタン（全幅）
            isDownloading.value
                ? Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                            value: progress.value, minHeight: 6),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () {
                          cancelToken.value?.cancel();
                        },
                        icon: const Icon(Icons.cancel,
                            color: Colors.red, size: 16),
                        label: Text(l10n.cancel,
                            style: const TextStyle(color: Colors.red)),
                      ),
                    ],
                  )
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCC0000),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 24),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                      shape: const StadiumBorder(),
                      elevation: 0,
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
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(!isAvailable
                          ? l10n.contentUnavailableButton
                          : downloaded
                              ? l10n.open
                              : '最新号をダウンロード'),
                    ),
                  ),

            // バックナンバーリンク
            if (!isDownloading.value) ...[
              const SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2A344B),
                  minimumSize: const Size(double.infinity, 48),
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 24),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                  shape: const StadiumBorder(
                      side: BorderSide(color: Color(0xFFB7C1CD))),
                  elevation: 0,
                ),
                onPressed: () => context.push('/backnumber'),
                child: const Text('バックナンバーを読む'),
              ),
            ],

            // 削除ボタン（ダウンロード済みのみ）
            if (downloaded && !isDownloading.value)
              Center(
                child: TextButton.icon(
                  onPressed: deleteFile,
                  icon: Icon(Icons.delete_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.error),
                  label: Text(l10n.deleteFile,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ),
              ),
          ],
        ),
      );
    }

    // ── standalone モード（従来スタイル：中央大型表示） ───────────────────
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
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

                Text(
                  content.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 8),

                Text(
                  content.description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black54),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 24),

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
                              onPressed: () => cancelToken.value?.cancel(),
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
    );
    return Center(child: SingleChildScrollView(child: body));
  }
}
