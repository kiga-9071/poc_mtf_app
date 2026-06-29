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

/// PDFの1ページ目サムネイルを大きく表示するグリッド用カードウィジェット。
/// - ダウンロード済み: PDFの1ページ目をサムネイル表示
/// - 未ダウンロード: PDFアイコンとダウンロードボタンのプレースホルダーを表示
/// - ダウンロード中: サムネイル領域に進捗オーバーレイを重ねて表示
///
/// レイアウト（mainAxisExtent: 300px 固定）:
///   - サムネイル領域: Expanded（A4比率でオーバーフロー+クリップ）
///   - 情報領域: 約115px（カテゴリ・タイトル・アクションボタン）
class ContentPreviewCard extends HookConsumerWidget {
  const ContentPreviewCard({
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
    // ダークモード判定（PDFサムネイルの背景色切替に使用）
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isDownloading = useState(false);
    // ダウンロード進捗（0.0 〜 1.0）
    final progress = useState(0.0);
    // ダウンロードごとに新しいトークンを生成するため useState で保持する
    final cancelToken = useState(CancelToken());
    final isDownloaded = useState(false);
    // 保存済みファイルのローカルパス（サムネイル表示に使用）
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.deletedMsg(content.title))),
        );
      }
    }

    final downloaded = isDownloaded.value;
    final path = savedPath.value;

    return Card(
      elevation: 2,
      // カード角丸をサムネイルにも適用するためクリップ
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── サムネイル領域 ────────────────────────────────────────────────
          // Expanded で残りの高さをすべて使用する
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // プレビュー画像（ダウンロード状態に関わらず常に表示）
                // 将来的にはAPIから取得した画像URLに置き換える予定
                Image.asset(
                  content.previewImageAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, _, __) => ColoredBox(
                    color: isDark
                        ? const Color(0xFF2C2C2C)
                        : const Color(0xFFF0F0F0),
                    child: Icon(
                      Icons.picture_as_pdf,
                      size: 52,
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                    ),
                  ),
                ),
                // ダウンロード中: 半透明オーバーレイに進捗を表示
                if (isDownloading.value)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            value: progress.value > 0 ? progress.value : null,
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
              ],
            ),
          ),

          // ── 情報領域 ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // カテゴリーバッジ・保存済みアイコン・削除ボタン
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(content.category,
                          style: const TextStyle(fontSize: 10)),
                    ),
                    if (downloaded) ...[
                      const SizedBox(width: 4),
                      // 保存済みアイコン
                      Icon(Icons.check_circle,
                          size: 14, color: Colors.green.shade600),
                    ],
                    const Spacer(),
                    // 保存済みの場合のみ削除ボタンを表示
                    if (downloaded)
                      GestureDetector(
                        onTap: deleteFile,
                        child: Icon(Icons.delete_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.error),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // タイトル（最大2行）
                Text(
                  content.title,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                // アクションボタン / ダウンロード進捗
                if (isDownloading.value)
                  // ダウンロード中: プログレスバー + キャンセルボタン
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress.value,
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => cancelToken.value.cancel(),
                        child: Icon(Icons.cancel,
                            size: 20,
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  )
                else if (downloaded)
                  // 保存済み: 開くボタン
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        minimumSize: const Size(0, 30),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      onPressed: path != null
                          ? () => context.go('/viewer', extra: path)
                          : null,
                      child: Text(l10n.open),
                    ),
                  )
                else
                  // 未ダウンロード: ダウンロードボタン
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        minimumSize: const Size(0, 30),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      onPressed: dirSnapshot.hasData ? download : null,
                      child: Text(l10n.downloadAndSave),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
