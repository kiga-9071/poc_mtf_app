import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../controllers/content_master_controller.dart';
import '../../entities/pdf_content.dart';
import '../../entities/viewer_args.dart';
import '../../l10n.dart';
import '../../services/storage_limit_service.dart';
import 'storage_limit_dialog.dart';
import '../../services/analytics_service.dart';
import '../../services/content_update_service.dart';
import '../../services/pdf_document_cache.dart';
import '../../services/pdf_preview_cache.dart';

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
    // ダークモード判定（PDFサムネイルの背景色切替に使用）
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isDownloading = useState(false);
    // ダウンロード進捗（0.0 〜 1.0）
    final progress = useState(0.0);
    // ローカル（dio）用キャンセルトークン
    final cancelToken = useState<CancelToken?>(null);
    // 外部URL（background_downloader）用タスク
    final currentBgTask = useState<DownloadTask?>(null);
    final isDownloaded = useState(false);
    final dio = useMemoized(() => Dio(BaseOptions(connectTimeout: const Duration(seconds: 3))));
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

    // ダウンロード済みPDFを事前にPdfiumで開いておき、ビューア起動を高速化する。
    // PdfPreviewCache: サムネイルJPEG生成（ビューア起動直後の空白を埋める）
    // PdfDocumentCache: Pdfiumドキュメントを事前オープン（ビューアのロード待ちをゼロにする）
    useEffect(() {
      final filePath = savedPath.value;
      if (filePath == null) return null;
      PdfPreviewCache.warmUp(filePath); // ignore: unawaited_futures
      PdfDocumentCache.warmUp(filePath); // ignore: unawaited_futures
      return null;
    }, [savedPath.value]);

    Future<void> download() async {
      if (dirSnapshot.data == null) return;

      // ── 容量上限チェック → 自動クリーンアップ ────────────────────────────
      final exceeded = await StorageLimitService.checkBeforeDownload();
      if (exceeded != null) {
        // マスターJSONの表示期間を参照して期限切れ・LRU順に自動削除を試みる
        final masterData = ref.read(contentMasterProvider).valueOrNull;
        final allContents =
            masterData?.contents.values.expand((l) => l) ?? [];
        final expirationByContentId = {
          for (final c in allContents) c.id: c.availableTo,
        };
        final deleted = await StorageLimitService.autoCleanup(
          expirationByContentId: expirationByContentId,
          dir: dirSnapshot.data!,
        );

        // クリーンアップ後に再チェック
        final stillExceeded = await StorageLimitService.checkBeforeDownload();
        if (stillExceeded != null) {
          // 自動削除しても空きが足りない場合はダイアログで案内
          if (context.mounted) {
            await showStorageLimitExceededDialog(
              context,
              usage: stillExceeded.usage,
              limit: stillExceeded.limit,
            );
          }
          return;
        }
        // 空きを確保できた場合はスナックバーで通知してダウンロードを続行
        if (context.mounted && deleted.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${deleted.length}件の古いキャッシュを削除して空き容量を確保しました'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      final path = buildSavePath(dirSnapshot.data!, content, langCode);
      isDownloading.value = true;
      progress.value = 0;

      AnalyticsService.logPdfDownloadStart(
        contentId: content.id,
        contentTitle: content.title,
      );

      final isLocal = content.url.startsWith('http://127.0.0.1');

      if (isLocal) {
        // ── ローカル（モックサーバー）: dio でダウンロード ─────────────────
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
          AnalyticsService.logPdfDownloadComplete(
            contentId: content.id,
            contentTitle: content.title,
          );
          // ignore: unawaited_futures
          ContentUpdateService.saveDownloadTimestamp(content.id, langCode);
          if (dirSnapshot.data != null) checkDownloadStatus(dirSnapshot.data!);
        } on DioException catch (e) {
          if (!context.mounted) return;
          cancelToken.value = null;
          if (e.type == DioExceptionType.cancel) {
            isDownloading.value = false;
            progress.value = 0;
            AnalyticsService.logPdfDownloadCancelled(
              contentId: content.id,
              contentTitle: content.title,
            );
            return;
          }
          // サーバー接続失敗時はバンドルアセットにフォールバック
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
            AnalyticsService.logPdfDownloadComplete(
              contentId: content.id,
              contentTitle: content.title,
            );
            // ignore: unawaited_futures
            ContentUpdateService.saveDownloadTimestamp(content.id, langCode);
            if (dirSnapshot.data != null) checkDownloadStatus(dirSnapshot.data!);
          } catch (fallbackErr) {
            if (!context.mounted) return;
            isDownloading.value = false;
            progress.value = 0;
            AnalyticsService.logPdfDownloadFailed(
              contentId: content.id,
              contentTitle: content.title,
              reason: '$fallbackErr',
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.downloadFailed('$fallbackErr'))),
            );
          }
        } catch (e) {
          if (!context.mounted) return;
          cancelToken.value = null;
          isDownloading.value = false;
          progress.value = 0;
          AnalyticsService.logPdfDownloadFailed(
            contentId: content.id,
            contentTitle: content.title,
            reason: '$e',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorMsg('$e'))),
          );
        }
      } else {
        // ── 外部URL: background_downloader でダウンロード ────────────────
        // buildSavePath と同じファイル名・同じ保存先ディレクトリを使用する。
        final filename = path.split('/').last;
        final task = DownloadTask(
          url: content.url,
          filename: filename,
          baseDirectory: BaseDirectory.applicationDocuments,
          updates: Updates.statusAndProgress,
        );
        currentBgTask.value = task;

        final result = await FileDownloader().download(
          task,
          onProgress: (p) {
            if (context.mounted) progress.value = p.clamp(0.0, 1.0);
          },
        );

        currentBgTask.value = null;
        if (!context.mounted) return;

        switch (result.status) {
          case TaskStatus.complete:
            isDownloading.value = false;
            // ignore: unawaited_futures
            StorageLimitService.recordFile(
                path.split('/').last, File(path).lengthSync(), content.id);
            AnalyticsService.logPdfDownloadComplete(
              contentId: content.id,
              contentTitle: content.title,
            );
            // ignore: unawaited_futures
            ContentUpdateService.saveDownloadTimestamp(content.id, langCode);
            if (dirSnapshot.data != null) checkDownloadStatus(dirSnapshot.data!);
          case TaskStatus.canceled:
            isDownloading.value = false;
            progress.value = 0;
            AnalyticsService.logPdfDownloadCancelled(
              contentId: content.id,
              contentTitle: content.title,
            );
          default:
            isDownloading.value = false;
            progress.value = 0;
            AnalyticsService.logPdfDownloadFailed(
              contentId: content.id,
              contentTitle: content.title,
              reason: '${result.status}',
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.downloadFailed('${result.status}'))),
            );
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
      if (await file.exists()) {
        PdfDocumentCache.evict(path);
        await StorageLimitService.removeFile(path.split('/').last);
        await file.delete();
      }
      AnalyticsService.logPdfDelete(
        contentId: content.id,
        contentTitle: content.title,
      );
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

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A2A344B),
            blurRadius: 10,
            spreadRadius: -2,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                  alignment: content.isWebContent
                      ? Alignment.topCenter
                      : Alignment.center,
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

          // ── 情報領域（高さ固定でサムネイル高さを安定させる） ───────────────
          SizedBox(
            height: 122,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // カテゴリーバッジ・保存済みアイコン・削除ボタン
                  // Expanded で左グループを確保し、削除ボタンは右端に固定する。
                  // Spacer と Flexible を同列に置くと固定要素が増えたときに
                  // カテゴリーバッジ幅がパディング以下に圧縮される問題を防ぐ。
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE1E3E6),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Text(
                                  content.category,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w300,
                                      color: Colors.black),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (!isAvailable) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border:
                                      Border.all(color: Colors.red.shade300),
                                ),
                                child: Text(
                                  content.availableTo != null &&
                                          DateTime.now()
                                              .isAfter(content.availableTo!)
                                      ? l10n.contentExpired
                                      : l10n.contentNotYet,
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.red.shade700),
                                ),
                              ),
                            ] else if (downloaded) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.check_circle,
                                  size: 14, color: Colors.green.shade600),
                            ],
                          ],
                        ),
                      ),
                      if (downloaded)
                        GestureDetector(
                          onTap: deleteFile,
                          child: Icon(Icons.delete_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.error),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // タイトル（2行分の高さを固定してサムネイルがずれないようにする）
                  SizedBox(
                    height: 42,
                    child: Text(
                      content.title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.white : Colors.black),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // アクションボタン / ダウンロード進捗（残り高さを埋める）
                  Expanded(
                    child: Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: double.infinity,
                        child: content.isWebContent
                            // Webコンテンツ: ChromeSafariBrowser で開く
                            ? ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  minimumSize: const Size(0, 28),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(fontSize: 11),
                                ),
                                onPressed: !isAvailable
                                    ? null
                                    : () async {
                                        AnalyticsService.logWebContentOpen(
                                          contentId: content.id,
                                          contentTitle: content.title,
                                        );
                                        final browser = ChromeSafariBrowser();
                                        await browser.open(
                                          url: WebUri(content.url),
                                          settings: ChromeSafariBrowserSettings(
                                            presentationStyle:
                                                ModalPresentationStyle.FULL_SCREEN,
                                            barCollapsingEnabled: true,
                                          ),
                                        );
                                      },
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(!isAvailable
                                      ? l10n.contentUnavailableButton
                                      : l10n.openOnWeb),
                                ),
                              )
                            : isDownloading.value
                                // ダウンロード中: プログレスバー + キャンセルボタン
                                ? Row(
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
                                        onTap: () {
                                          cancelToken.value?.cancel();
                                          final bgTask = currentBgTask.value;
                                          if (bgTask != null) {
                                            FileDownloader().cancel(bgTask);
                                          }
                                        },
                                        child: Icon(Icons.cancel,
                                            size: 20,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error),
                                      ),
                                    ],
                                  )
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      minimumSize: const Size(0, 28),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      textStyle: const TextStyle(fontSize: 11),
                                    ),
                                    onPressed: !isAvailable
                                        ? null
                                        : downloaded
                                            ? (path != null
                                                ? () {
                                                    AnalyticsService.logPdfOpen(
                                                      contentId: content.id,
                                                      contentTitle: content.title,
                                                    );
                                                    // LRU 管理のためアクセス日時を更新
                                                    StorageLimitService
                                                        .recordAccess(
                                                            path.split('/').last);
                                                    context.push('/viewer',
                                                        extra: ViewerArgs(
                                                            filePath: path,
                                                            preventCapture: content
                                                                .preventCapture));
                                                  }
                                                : null)
                                            : (dirSnapshot.hasData ? download : null),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(!isAvailable
                                          ? l10n.contentUnavailableButton
                                          : downloaded
                                              ? l10n.open
                                              : l10n.downloadAndSave),
                                    ),
                                  ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}
