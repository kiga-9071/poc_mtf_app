import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:ui' as ui;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../services/capture_protection_service.dart';

import '../../controllers/bookmark_controller.dart';
import '../../controllers/memo_controller.dart';
import '../../entities/search_match.dart';
import '../../l10n.dart';
import '../pdf_viewer/pdf_viewer_constants.dart';
import 'pdf_link_overlay.dart';
import 'pdf_search_highlight.dart';
import 'pdf_tts_highlight.dart';
import 'pdf_search_nav_bar.dart';
import 'pdf_mini_map.dart';
import 'pdf_side_drawer.dart';
import 'pdf_thumbnail_strip.dart';
import 'pdf_top_bar.dart';
import '../../webview/webview_page.dart';

/// PDFを表示するメイン画面。
///
/// - PageView による横スワイプでページ切り替え
/// - InteractiveViewer によるピンチズーム
/// - サイドドロワー（目次・ブックマーク・キーワード検索）
/// - 上部: PdfTopBar（メニュー・ブックマーク）
/// - 下部: PdfThumbnailStrip（ページ一覧・タップでジャンプ）
/// - キーワード検索: PdfSearchNavBar + PdfSearchHighlightOverlay
class PdfViewerPage extends HookConsumerWidget {
  const PdfViewerPage({
    super.key,
    this.initialFilePath,
    this.preventCapture = false,
  });

  /// コンテンツ一覧から遷移してきた場合のローカルファイルパス
  final String? initialFilePath;

  /// true のとき OS レベルでスクリーンショット・録画を抑止する。
  /// Android: FLAG_SECURE / iOS: セキュアテキスト入力トリック + バックグラウンド時オーバーレイ
  final bool preventCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ダークモードが有効かどうか（PDFページ色反転に使用）
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Scaffold の Key: ドロワーをコードから開閉するために必要
    final scaffoldKey = useMemoized(() => GlobalKey<ScaffoldState>());

    // ビューアー起動時刻（PDFロードにかかった時間の計測用）
    final viewerOpenedAt = useMemoized(() => DateTime.now());

    // 現在開いているPDFファイル（null = ファイル未選択）
    final selectedFile = useState<File?>(null);
    // 総ページ数（0 = 未ロード）
    final pageCount = useState(0);
    // 現在表示中のページ番号（1始まり）
    final currentPage = useState(1);
    // PDFの目次ノードリスト
    final outline = useState<List<PdfOutlineNode>>([]);
    // pdfrx の PdfDocument インスタンス
    final document = useState<PdfDocument?>(null);
    // ブックマーク済みページ番号のセット（BookmarkController から復元）
    final bookmarks = useState<Set<int>>({});
    // ページ番号→メモテキストのマップ（MemoController から復元）
    final memos = useState<Map<int, String>>({});
    // AppBar とサムネイルバーの表示/非表示フラグ（タップで切り替え）
    final isUiVisible = useState(true);
    // 現在の検索クエリ文字列（ハイライト表示に使用）
    final searchQuery = useState<String>('');
    // キーワード検索のヒット一覧（全ページ分）
    final searchMatches = useState<List<SearchMatch>>([]);
    // 現在フォーカスされている検索ヒットのインデックス（0始まり）
    final searchIndex = useState<int>(0);

    // TTS（読み上げ）のステータス
    final ttsStatus = useState(TtsStatus.idle);
    // TTS 読み上げ中の現在単語ハイライト範囲（文字インデックス）
    final ttsHighlightStart = useState<int?>(null);
    final ttsHighlightEnd = useState<int?>(null);
    // TTS 読み上げ中ページのテキストキャッシュ（ハイライト座標変換に使用）
    final ttsPageText = useState<PdfPageText?>(null);

    // ピンチズーム用コントローラー。
    // 倍率を監視して PageView のスワイプと干渉しないよう制御する。
    final transformController = useMemoized(() => TransformationController());
    useEffect(() => transformController.dispose, [transformController]);

    // ページが拡大中かどうか（true のとき PageView のスワイプを無効化）。
    // useState ではなく ValueNotifier にすることで、ズーム状態の変化が
    // PdfViewerPage.build() 全体の再実行を引き起こさない。
    // PageView の physics と InteractiveViewer の panEnabled は
    // ValueListenableBuilder 経由で最小スコープだけ再描画される。
    final isZoomedNotifier = useMemoized(() => ValueNotifier<bool>(false));
    useEffect(() => isZoomedNotifier.dispose, [isZoomedNotifier]);

    // TransformationController の変化を監視してズーム状態を更新する
    useEffect(() {
      void onTransform() {
        final zoomed = transformController.value.getMaxScaleOnAxis() > 1.05;
        if (isZoomedNotifier.value != zoomed) isZoomedNotifier.value = zoomed;
      }
      transformController.addListener(onTransform);
      return () => transformController.removeListener(onTransform);
    }, [transformController]);

    // ページが変わったらズームを 1.0 にリセットする
    useEffect(() {
      transformController.value = Matrix4.identity();
      return null;
    }, [currentPage.value]);

    // ズームアウト（1.0x 未満）から指を離したとき 1.0x へスナップするアニメーション。
    // useAnimationController は flutter_hooks が自動 dispose する。
    final snapAnimController = useAnimationController(
      duration: const Duration(milliseconds: 280),
    );
    // スナップ開始時点の行列を保持する（アニメーション中の begin として使用）
    final snapStartMatrix = useRef<Matrix4?>(null);

    useEffect(() {
      void onSnap() {
        final start = snapStartMatrix.value;
        if (start == null) return;
        final t = Curves.easeOut.transform(snapAnimController.value);
        transformController.value = t >= 1.0
            ? Matrix4.identity()
            : Matrix4Tween(begin: start, end: Matrix4.identity()).lerp(t);
        if (t >= 1.0) snapStartMatrix.value = null;
      }
      snapAnimController.addListener(onSnap);
      return () => snapAnimController.removeListener(onSnap);
    }, [snapAnimController]);

    // ダブルタップズーム用アニメーションコントローラー
    final doubleTapZoomController = useAnimationController(
      duration: const Duration(milliseconds: 250),
    );
    final doubleTapStartMatrix = useRef<Matrix4?>(null);
    final doubleTapTargetMatrix = useRef<Matrix4?>(null);
    // ダブルタップした座標（ズームの中心点として使用）
    final doubleTapPosition = useRef<Offset>(Offset.zero);

    useEffect(() {
      void onDoubleTapZoom() {
        final start = doubleTapStartMatrix.value;
        final target = doubleTapTargetMatrix.value;
        if (start == null || target == null) return;
        final t = Curves.easeInOut.transform(doubleTapZoomController.value);
        transformController.value =
            Matrix4Tween(begin: start, end: target).lerp(t);
      }
      doubleTapZoomController.addListener(onDoubleTapZoom);
      return () => doubleTapZoomController.removeListener(onDoubleTapZoom);
    }, [doubleTapZoomController]);

    // TTS インスタンス（ウィジェットのライフサイクルで一度だけ生成）
    final tts = useMemoized(() => FlutterTts());

    useEffect(() {
      void resetTts() {
        ttsStatus.value = TtsStatus.idle;
        ttsHighlightStart.value = null;
        ttsHighlightEnd.value = null;
        ttsPageText.value = null;
      }
      // キャンセル・エラー時のフォールバックリセット
      // （completionHandler と progressHandler はセッションごとに toggleTts で登録する）
      tts.setCancelHandler(resetTts);
      tts.setErrorHandler((_) => resetTts());
      // iOS: オーディオセッションを有効化しないと音声が出ない場合がある
      if (Platform.isIOS) {
        tts.setSharedInstance(true);
      }
      return () { tts.stop(); };
    }, []);

    // テキスト選択オーバーレイ用の共有マップ（ページをまたいで選択状態を管理）
    final selectables =
        useMemoized(() => SplayTreeMap<int, PdfPageTextSelectable>());

    // コンテンツ一覧からファイルパスが渡された場合に自動でファイルを開く
    useEffect(() {
      if (initialFilePath != null) {
        selectedFile.value = File(initialFilePath!);
      }
      return null;
    }, []);

    // preventCapture が true のとき OS レベルでキャプチャを抑止する。
    // Android: MainActivity の MethodChannel 経由で FLAG_SECURE を直接設定する。
    // iOS: screen_protector の UITextField トリック + バックグラウンド時の黒オーバーレイ。
    useEffect(() {
      if (!preventCapture) return null;
      debugPrint('[PdfViewer] captureProtection: enable');
      CaptureProtectionService.enable();
      return () {
        debugPrint('[PdfViewer] captureProtection: disable');
        CaptureProtectionService.disable();
      };
    }, const []);

    // ファイルが変わったらブックマーク・メモをストレージから読み込む
    useEffect(() {
      final path = selectedFile.value?.path;
      if (path == null) {
        bookmarks.value = {};
        memos.value = {};
        return null;
      }
      loadBookmarks(path).then((saved) => bookmarks.value = saved);
      loadMemos(path).then((saved) => memos.value = saved);
      return null;
    }, [selectedFile.value?.path]);

    // ファイルが変わるたびに新しいコントローラーを生成してページ 0 にリセット
    final pageController = useMemoized(
      () => PageController(initialPage: 0),
      [selectedFile.value],
    );

    final thumbnailScrollController = useMemoized(() => ScrollController());

    // 現在ページが変わるたびにサムネイルストリップを自動スクロールする
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (thumbnailScrollController.hasClients &&
            thumbnailScrollController.position.hasContentDimensions) {
          final offset =
              (currentPage.value - 1) * (kPdfThumbnailWidth + 8) -
                  thumbnailScrollController.position.viewportDimension / 2 +
                  kPdfThumbnailWidth / 2;
          thumbnailScrollController.animateTo(
            offset.clamp(
                0, thumbnailScrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      });
      return null;
    }, [currentPage.value]);

    // ページが変わったら読み上げを停止する
    useEffect(() {
      if (ttsStatus.value != TtsStatus.idle) {
        tts.stop();
        ttsStatus.value = TtsStatus.idle;
        ttsHighlightStart.value = null;
        ttsHighlightEnd.value = null;
        ttsPageText.value = null;
      }
      return null;
    }, [currentPage.value]);

    /// ダブルタップでズームイン（2x）／ズームアウト（1x）を切り替える。
    /// タップ位置を中心にアニメーションする。
    void handleDoubleTap() {
      snapAnimController.stop();
      final isZoomed = transformController.value.getMaxScaleOnAxis() > 1.5;
      doubleTapStartMatrix.value = transformController.value.clone();
      if (isZoomed) {
        doubleTapTargetMatrix.value = Matrix4.identity();
      } else {
        const scale = 2.0;
        final f = doubleTapPosition.value;
        // T(f) * S(scale) * T(-f) を展開した行列:
        // 変換成分 = f * (1 - scale) で焦点を固定したままスケールする
        doubleTapTargetMatrix.value = Matrix4.identity()
          ..setEntry(0, 0, scale)
          ..setEntry(1, 1, scale)
          ..setEntry(0, 3, f.dx * (1 - scale))
          ..setEntry(1, 3, f.dy * (1 - scale));
      }
      doubleTapZoomController.forward(from: 0.0);
    }

    /// TTS の読み上げ開始・停止を切り替える。
    /// 読み上げ中に呼ぶと停止、停止中に呼ぶと現在ページのテキストを読み上げる。
    Future<void> toggleTts() async {
      if (ttsStatus.value != TtsStatus.idle) {
        await tts.stop();
        ttsStatus.value = TtsStatus.idle;
        ttsHighlightStart.value = null;
        ttsHighlightEnd.value = null;
        ttsPageText.value = null;
        return;
      }

      final doc = document.value;
      if (doc == null || pageCount.value == 0) return;

      ttsStatus.value = TtsStatus.loading;

      // context 使用は最初の await より前に行う
      final langCode = Localizations.localeOf(context).languageCode;

      try {
        final page = doc.pages[currentPage.value - 1];
        final pageText = await page.loadText();
        final nativeText = pageText.fullText.trim();
        debugPrint('[TTS] loadText length=${nativeText.length}, lang=$langCode');
        debugPrint('[TTS] nativeText[:80]="${nativeText.substring(0, nativeText.length.clamp(0, 80))}"');

        bool usedOcr;
        String speakText;
        if (nativeText.isNotEmpty) {
          // フラグメントを座標でソートして視覚的な読み順に並べ直す
          usedOcr = false;
          ttsPageText.value = pageText;
          speakText = _extractTtsText(pageText);
        } else {
          // テキスト層なし → iOS は PDFKit でテキスト抽出を試みる
          usedOcr = false;
          speakText = '';
          final filePath = selectedFile.value?.path;
          if (filePath != null && Platform.isIOS) {
            const _kPdfChannel = MethodChannel('app.tts.pdf');
            try {
              final pdfKitText = await _kPdfChannel.invokeMethod<String>(
                    'extractText',
                    {'filePath': filePath, 'pageIndex': currentPage.value - 1},
                  ) ?? '';
              debugPrint('[TTS] PDFKit result length=${pdfKitText.length}');
              if (pdfKitText.trim().isNotEmpty) {
                speakText = pdfKitText.trim();
              }
            } catch (e) {
              debugPrint('[TTS] PDFKit error: $e');
            }
          }
          // PDFKit でも取得できなければ OCR フォールバック
          if (speakText.isEmpty) {
            usedOcr = true;
            if (filePath != null) {
              speakText = await _extractTextByOcr(filePath, currentPage.value - 1, langCode);
            }
            debugPrint('[TTS] OCR result length=${speakText.length}');
          }
        }

        if (speakText.isEmpty) {
          ttsStatus.value = TtsStatus.idle;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppL10n.of(context).ttsNoText)),
            );
          }
          return;
        }

        // ネイティブテキストパスで日本語が検出されない場合、フォントのToUnicode不足の可能性があるためOCRにフォールバック
        if (!usedOcr &&
            langCode == 'ja' &&
            !speakText.contains(RegExp(r'[぀-ゟ゠-ヿ一-龯]'))) {
          final filePath = selectedFile.value?.path;
          if (filePath != null) {
            debugPrint('[TTS] native text has no Japanese (ToUnicode missing?), trying OCR fallback');
            final ocrText = await _extractTextByOcr(
                filePath, currentPage.value - 1, langCode);
            debugPrint('[TTS] OCR fallback length=${ocrText.length}');
            if (ocrText.isNotEmpty) {
              speakText = ocrText;
              usedOcr = true;
              ttsPageText.value = null; // OCRパスではハイライト不可
            }
          }
        }

        // ── テキスト診断ログ ──────────────────────────────────────────
        final hasJapanese = speakText.contains(
          RegExp(r'[぀-ゟ゠-ヿ一-龯]'),
        );
        final useJapanese = langCode == 'ja' || hasJapanese;
        debugPrint('[TTS] hasJapanese=$hasJapanese useJapanese=$useJapanese '
            'speakLen=${speakText.length}');
        debugPrint('[TTS] speakText[:100]="${speakText.substring(0, speakText.length.clamp(0, 100))}"');
        // ─────────────────────────────────────────────────────────────

        if (Platform.isIOS && useJapanese) {
          // clearVoice で前回の音声設定をリセットしてから日本語音声を指定する。
          // flutter_tts 4.2.5 は identifier があれば AVSpeechSynthesisVoice(identifier:)
          // で音声を確定できるため、name+locale の文字列一致より確実。
          await tts.clearVoice();
          final rawVoices = await tts.getVoices;
          final voices =
              (rawVoices as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
          final jaVoices = voices
              .where((v) => (v['locale'] as String? ?? '').startsWith('ja'))
              .toList();
          debugPrint('[TTS] iOS ja voices: '
              '${jaVoices.map((v) => '${v['name']}(${v['quality']})').toList()}');

          // compact（OS 標準）を優先し、なければ先頭の日本語音声を使う
          Map<dynamic, dynamic>? jaVoice;
          for (final v in jaVoices) {
            if ((v['quality'] as String? ?? '') == 'compact') {
              jaVoice = v;
              break;
            }
          }
          jaVoice ??= jaVoices.isNotEmpty ? jaVoices.first : null;

          if (jaVoice != null) {
            final r = await tts.setVoice({
              'name': jaVoice['name'].toString(),
              'locale': jaVoice['locale'].toString(),
              'identifier': (jaVoice['identifier'] ?? '').toString(),
            });
            debugPrint('[TTS] iOS setVoice result=$r '
                'name=${jaVoice['name']} id=${jaVoice['identifier']}');
            if (r != 1) {
              // setVoice 失敗時は setLanguage にフォールバック
              final lr = await tts.setLanguage('ja-JP');
              debugPrint('[TTS] iOS setLanguage fallback result=$lr');
            }
          } else {
            final lr = await tts.setLanguage('ja-JP');
            debugPrint('[TTS] iOS no ja voice, setLanguage result=$lr');
          }
        } else {
          await tts.setLanguage(useJapanese ? 'ja-JP' : 'en-US');
        }

        // iOS の AVSpeechSynthesizer は長文で途中停止するため、チャンク分割して逐次読み上げる
        final chunks = _buildTtsChunks(speakText);
        var chunkIndex = 0;
        debugPrint('[TTS] chunks=${chunks.length}, total=${speakText.length}chars');

        // チャンク完了時に次チャンクへ進む。最終チャンクで状態をリセット。
        tts.setCompletionHandler(() {
          if (!context.mounted) return;
          chunkIndex++;
          if (chunkIndex < chunks.length &&
              ttsStatus.value == TtsStatus.speaking) {
            tts.speak(chunks[chunkIndex]);
          } else {
            ttsStatus.value = TtsStatus.idle;
            ttsHighlightStart.value = null;
            ttsHighlightEnd.value = null;
            ttsPageText.value = null;
          }
        });

        // ハイライトは先頭チャンクのみ有効（チャンク境界でインデックスがリセットされるため）
        tts.setProgressHandler((text, start, end, word) {
          if (!context.mounted || ttsPageText.value == null) return;
          if (chunkIndex == 0) {
            ttsHighlightStart.value = start;
            ttsHighlightEnd.value = end;
          }
        });

        ttsStatus.value = TtsStatus.speaking;
        await tts.speak(chunks[0]);
      } catch (e, st) {
        debugPrint('[TTS] error: $e\n$st');
        ttsStatus.value = TtsStatus.idle;
        ttsPageText.value = null;
      }
    }

    // goToPage によるプログラム遷移中フラグ。
    // animateToPage が経由ページで onPageChanged を発火させ currentPage を
    // 上書きするのを防ぐために使用する。
    final isProgrammaticNav = useRef(false);

    /// 指定ページ番号に移動する（PageView アニメーション付き）。
    void goToPage(int page) {
      isProgrammaticNav.value = true;
      currentPage.value = page;
      pageController
          .animateToPage(
            page - 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          )
          .then((_) => isProgrammaticNav.value = false);
    }

    /// 現在ページのブックマーク状態を切り替え、BookmarkController で永続化する。
    void toggleBookmark() {
      final page = currentPage.value;
      final updated = Set<int>.from(bookmarks.value);
      updated.contains(page) ? updated.remove(page) : updated.add(page);
      bookmarks.value = updated;
      if (selectedFile.value != null) {
        saveBookmarks(selectedFile.value!.path, updated);
      }
    }

    /// scale が 1.0 未満のとき 1.0x へのスナップアニメーションを開始する。
    void snapBackToFit() {
      if (transformController.value.getMaxScaleOnAxis() < 1.0 - 0.02) {
        snapStartMatrix.value = transformController.value.clone();
        snapAnimController.forward(from: 0.0);
      }
    }

    /// 現在ページのメモ編集ダイアログを表示する。
    void showMemoDialog(int page) {
      final l10n = AppL10n.of(context);
      final controller =
          TextEditingController(text: memos.value[page] ?? '');
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${l10n.memo} — $page ${l10n.page}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 6,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l10n.memoHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (memos.value.containsKey(page))
                      TextButton(
                        onPressed: () {
                          final updated =
                              Map<int, String>.from(memos.value);
                          updated.remove(page);
                          memos.value = updated;
                          if (selectedFile.value != null) {
                            saveMemos(selectedFile.value!.path, updated);
                          }
                          Navigator.of(ctx).pop();
                        },
                        child: Text(l10n.delete,
                            style: const TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final text = controller.text.trim();
                        final updated =
                            Map<int, String>.from(memos.value);
                        if (text.isEmpty) {
                          updated.remove(page);
                        } else {
                          updated[page] = text;
                        }
                        memos.value = updated;
                        if (selectedFile.value != null) {
                          saveMemos(selectedFile.value!.path, updated);
                        }
                        Navigator.of(ctx).pop();
                      },
                      child: Text(l10n.save),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }

    /// 検索ヒットを次へ移動（末尾に達したら先頭に戻る循環ナビゲーション）。
    void searchGoNext() {
      if (searchMatches.value.isEmpty) return;
      final idx = (searchIndex.value + 1) % searchMatches.value.length;
      searchIndex.value = idx;
      goToPage(searchMatches.value[idx].pageNumber);
    }

    /// 検索ヒットを前へ移動（先頭に達したら末尾に戻る循環ナビゲーション）。
    void searchGoPrev() {
      if (searchMatches.value.isEmpty) return;
      final idx = (searchIndex.value - 1 + searchMatches.value.length) %
          searchMatches.value.length;
      searchIndex.value = idx;
      goToPage(searchMatches.value[idx].pageNumber);
    }

    final isBookmarked = bookmarks.value.contains(currentPage.value);
    final hasMemo = memos.value.containsKey(currentPage.value);

    // UI 表示切替のタップ判定用（Listener でジェスチャーアリーナに参加しない）
    final tapDownTime = useRef<DateTime?>(null);
    final tapDownPos  = useRef<Offset?>(null);

    // 画面に触れている指の本数。useState ではなく ValueNotifier にすることで、
    // タッチのたびに PdfViewerPage.build が再実行されるのを防ぐ。
    // build 再実行は PdfDocumentViewBuilder.didUpdateWidget を引き起こし、
    // _onDocumentChanged → setState → loadPagesProgressively の連鎖が生じて
    // PageView のスクロールジェスチャーを破壊する。
    final pointerCountNotifier = useMemoized(() => ValueNotifier<int>(0));
    useEffect(() => pointerCountNotifier.dispose, [pointerCountNotifier]);

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: Colors.black,
      drawer: PdfSideDrawer(
        outline: outline.value,
        bookmarks: bookmarks.value,
        memos: memos.value,
        filePath: selectedFile.value?.path,
        onOutlineTap: (dest) => goToPage(dest.pageNumber),
        onBookmarkTap: goToPage,
        onBookmarkDelete: (page) {
          final updated = Set<int>.from(bookmarks.value);
          updated.remove(page);
          bookmarks.value = updated;
          if (selectedFile.value != null) {
            saveBookmarks(selectedFile.value!.path, updated);
          }
        },
        onMemoTap: goToPage,
        onMemoDelete: (page) {
          final updated = Map<int, String>.from(memos.value);
          updated.remove(page);
          memos.value = updated;
          if (selectedFile.value != null) {
            saveMemos(selectedFile.value!.path, updated);
          }
        },
        onSearchDone: (query, matches) {
          searchQuery.value = query;
          searchMatches.value = matches;
          searchIndex.value = 0;
          if (matches.isNotEmpty) goToPage(matches[0].pageNumber);
        },
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── PDF本体 ───────────────────────────────────────────────────────
          Positioned.fill(
            child: selectedFile.value == null
                ? const SizedBox.shrink()
                : Listener(
                    // GestureDetector(onTap) の代わりに Listener を使う。
                    // Listener はジェスチャーアリーナに参加しないため
                    // SelectionArea の LongPressGestureRecognizer と競合せず、
                    // テキスト選択が 500ms の判定待ちなしに即座に始まる。
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (e) {
                      tapDownTime.value = DateTime.now();
                      tapDownPos.value  = e.localPosition;
                    },
                    onPointerUp: (e) {
                      final t = tapDownTime.value;
                      final p = tapDownPos.value;
                      tapDownTime.value = null;
                      tapDownPos.value  = null;
                      if (t == null || p == null) return;
                      final elapsed  = DateTime.now().difference(t);
                      final distance = (e.localPosition - p).distance;
                      // 250ms 以内かつ 20px 未満の動きのみタップと見なす
                      if (elapsed < const Duration(milliseconds: 250) &&
                          distance < 20) {
                        isUiVisible.value = !isUiVisible.value;
                      }
                    },
                    onPointerCancel: (_) {
                      tapDownTime.value = null;
                      tapDownPos.value  = null;
                    },
                    child: SelectionArea(
                    child: PdfDocumentViewBuilder.file(
                      selectedFile.value!.path,
                      key: ValueKey(selectedFile.value!.path),
                      builder: (context, doc) {
                        if (doc == null) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        // ページ数が確定したタイミングで状態を初期化
                        if (pageCount.value == 0 && doc.pages.isNotEmpty) {
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) async {
                            pageCount.value = doc.pages.length;
                            document.value = doc;
                            outline.value = await doc.loadOutline();
                            final ms = DateTime.now()
                                .difference(viewerOpenedAt)
                                .inMilliseconds;
                            debugPrint(
                                '[PDF Load] ${(ms / 1000).toStringAsFixed(2)}秒');
                          });
                        }
                        // 指の本数を追跡して PageView のスワイプを即座に無効化する。
                        // isZoomed の更新を待つと「倍率が上がる前に PageView が
                        // スワイプを横取りする」問題が生じるため、2本目の指が
                        // 触れた瞬間に NeverScrollableScrollPhysics に切り替える。
                        // ValueNotifier + ValueListenableBuilder を使い、
                        // physics だけをピンポイントで更新することで PdfViewerPage.build
                        // の再実行を防ぎ、スクロール中の不要な rebuild チェーンを断ち切る。
                        return Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: (_) {
                            snapAnimController.stop();
                            pointerCountNotifier.value++;
                          },
                          onPointerUp: (_) {
                            pointerCountNotifier.value =
                                (pointerCountNotifier.value - 1).clamp(0, 10);
                            if (pointerCountNotifier.value == 0) {
                              snapBackToFit();
                            }
                          },
                          onPointerCancel: (_) {
                            pointerCountNotifier.value =
                                (pointerCountNotifier.value - 1).clamp(0, 10);
                            if (pointerCountNotifier.value == 0) {
                              snapBackToFit();
                            }
                          },
                          // isZoomedNotifier と pointerCountNotifier を
                          // ValueListenableBuilder でネストし、physics と
                          // panEnabled の更新を PageView サブツリーに限定する。
                          // これにより PdfViewerPage.build() 全体の再実行を避け、
                          // ズーム状態の切り替えを即座かつ低コストで反映できる。
                          child: ValueListenableBuilder<bool>(
                            valueListenable: isZoomedNotifier,
                            builder: (_, isZoomed, __) =>
                            ValueListenableBuilder<int>(
                            valueListenable: pointerCountNotifier,
                            builder: (_, count, __) => PageView.builder(
                          controller: pageController,
                          physics: (isZoomed || count >= 2)
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(),
                          allowImplicitScrolling: true,
                          itemCount: doc.pages.length,
                          onPageChanged: (index) {
                            // プログラム遷移中は経由ページによる上書きを無視する
                            if (!isProgrammaticNav.value) {
                              currentPage.value = index + 1;
                            }
                            // ページ切り替え時にポインター数をリセット。
                            // 切り替えアニメーション中に pointer cancel が
                            // 届かない場合でも確実に 0 に戻す。
                            pointerCountNotifier.value = 0;
                          },
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onDoubleTapDown: (details) {
                                doubleTapPosition.value =
                                    details.localPosition;
                              },
                              onDoubleTap: handleDoubleTap,
                              child: InteractiveViewer(
                              transformationController: transformController,
                              minScale: 0.3,
                              maxScale: 5.0,
                              // EdgeInsets.all(infinity) でビューポート充填の強制を
                              // 解除し、1.0x 未満へのズームアウトを許可する。
                              // デフォルト zero だと InteractiveViewer が内部で
                              // "コンテンツがビューポートを満たす最小倍率" を算出し、
                              // それ以下へのスケールをブロックしてしまう。
                              boundaryMargin: const EdgeInsets.all(double.infinity),
                              // 非ズーム時はパンを無効化してジェスチャーアリーナへの
                              // 参加者を減らし、テキスト選択の応答性を高める。
                              panEnabled: isZoomed,
                              scaleEnabled: true,
                              child: PdfPageView(
                                document: doc,
                                pageNumber: index + 1,
                                maximumDpi: 150,
                                backgroundColor:
                                    isDark ? Colors.black : Colors.white,
                                // decorationBuilder: ページ画像の上にオーバーレイを重ねる
                                decorationBuilder:
                                    (ctx, pageSize, page, pageImage) {
                                  // ダークモード時: ページ画像に色反転フィルターを適用
                                  Widget? image = pageImage;
                                  if (isDark && image != null) {
                                    image = ColorFiltered(
                                      colorFilter: kPdfInvertColorFilter,
                                      child: image,
                                    );
                                  }
                                  return Align(
                                    alignment: Alignment.center,
                                    child: AspectRatio(
                                      aspectRatio:
                                          pageSize.width / pageSize.height,
                                      child: LayoutBuilder(
                                        builder: (ctx, constraints) {
                                          final size = Size(
                                            constraints.maxWidth,
                                            constraints.maxHeight,
                                          );
                                          return Stack(
                                            children: [
                                              // ページ背景（ダーク時は黒）
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? Colors.black
                                                      : Colors.white,
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Colors.black54,
                                                      blurRadius: 4,
                                                      offset: Offset(2, 2),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // PDFページ画像
                                              if (image != null) image,
                                              // 検索ハイライトオーバーレイ
                                              if (searchMatches
                                                  .value.isNotEmpty)
                                                Builder(builder: (_) {
                                                  final idx =
                                                      searchIndex.value;
                                                  final ms =
                                                      searchMatches.value;
                                                  // このページにフォーカスヒットがあるか確認
                                                  final activeMatch = (ms
                                                              .isNotEmpty &&
                                                          idx < ms.length &&
                                                          ms[idx].pageNumber ==
                                                              page.pageNumber)
                                                      ? ms[idx]
                                                      : null;
                                                  return PdfSearchHighlightOverlay(
                                                    page: page,
                                                    pageSize: size,
                                                    query: searchQuery.value,
                                                    activeMatch: activeMatch,
                                                  );
                                                }),
                                              // TTS 読み上げ中の現在単語ハイライト
                                              if (ttsHighlightStart.value != null &&
                                                  ttsHighlightEnd.value != null &&
                                                  ttsPageText.value != null &&
                                                  page.pageNumber == currentPage.value)
                                                PdfTtsHighlightOverlay(
                                                  page: page,
                                                  pageSize: size,
                                                  pageText: ttsPageText.value!,
                                                  charStart: ttsHighlightStart.value!,
                                                  charEnd: ttsHighlightEnd.value!,
                                                ),
                                              // テキスト選択オーバーレイ
                                              // ロングプレスで文字選択、コンテキストメニューからコピー可能
                                              PdfPageTextOverlay(
                                                selectables: selectables,
                                                page: page,
                                                pageRect: Rect.fromLTWH(
                                                    0, 0, size.width, size.height),
                                                selectionColor: Colors.blue
                                                    .withValues(alpha: 0.3),
                                                enabled: true,
                                              ),
                                              // PDFリンクオーバーレイ
                                              PdfLinkOverlay(
                                                page: page,
                                                pageSize: size,
                                                onUrlLink: (url) {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          WebViewPage(
                                                              url: url
                                                                  .toString()),
                                                    ),
                                                  );
                                                },
                                                onDestLink: (dest) =>
                                                    goToPage(dest.pageNumber),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),   // InteractiveViewer
                            );   // GestureDetector
                          },
                        ),   // PageView.builder
                          ),   // ValueListenableBuilder<int>
                          ),   // ValueListenableBuilder<bool>
                        );   // Listener
                      },
                    ),
                  ),
                  ),
          ),

          // ── ミニマップ ────────────────────────────────────────────────────
          if (selectedFile.value != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
              right: 16,
              child: PdfMiniMap(
                filePath: selectedFile.value!.path,
                pageNumber: currentPage.value,
                transformController: transformController,
                viewportSize: MediaQuery.of(context).size,
              ),
            ),

          // ── トップバー ────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              offset: isUiVisible.value ? Offset.zero : const Offset(0, -1),
              duration: kPdfBarDuration,
              curve: Curves.easeInOut,
              child: PdfTopBar(
                title: selectedFile.value != null
                    ? selectedFile.value!.path.split('/').last
                    : 'PDF Viewer',
                currentPage: currentPage.value,
                pageCount: pageCount.value,
                isBookmarked: isBookmarked,
                hasMemo: hasMemo,
                onMenuTap: () =>
                    scaffoldKey.currentState?.openDrawer(),
                onBookmarkTap:
                    pageCount.value > 0 ? toggleBookmark : null,
                onMemoTap: pageCount.value > 0
                    ? () => showMemoDialog(currentPage.value)
                    : null,
                onBack: () => context.go('/'),
                ttsStatus: ttsStatus.value,
                onTtsTap: toggleTts,
              ),
            ),
          ),

          // ── 検索ナビバー ──────────────────────────────────────────────────
          if (searchMatches.value.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight,
              left: 0,
              right: 0,
              child: PdfSearchNavBar(
                query: searchQuery.value,
                totalCount: searchMatches.value.length,
                currentIndex: searchIndex.value,
                currentPage:
                    searchMatches.value[searchIndex.value].pageNumber,
                onClose: () {
                  searchQuery.value = '';
                  searchMatches.value = [];
                },
                onPrev: searchGoPrev,
                onNext: searchGoNext,
              ),
            ),

          // ── サムネイルストリップ ───────────────────────────────────────────
          if (selectedFile.value != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedSlide(
                offset: isUiVisible.value
                    ? Offset.zero
                    : const Offset(0, 1),
                duration: kPdfBarDuration,
                curve: Curves.easeInOut,
                child: PdfThumbnailStrip(
                  filePath: selectedFile.value!.path,
                  pageCount: pageCount.value,
                  currentPage: currentPage.value,
                  bookmarks: bookmarks.value,
                  scrollController: thumbnailScrollController,
                  onPageTap: goToPage,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// PDF のテキストフラグメントを視覚的な読み順（上→下・左→右）にソートして結合する。
///
/// pdfrx の [PdfPageText.fullText] はフラグメントを PDF 内部順（オブジェクト登録順）で
/// 連結するため、複数カラムや複雑レイアウトでは視覚的な読み順と一致しない。
/// フラグメントの [PdfRect] を使って座標ソートすることで読み順を修正する。
///
/// pdfrx の [PdfRect] は PDF 座標系（Y 上向き）なので top > bottom。
/// 視覚的に上にある要素ほど top が大きいため、top **降順** → left 昇順でソートする。
String _extractTtsText(PdfPageText pageText) {
  final frags = List.of(pageText.fragments);
  frags.sort((a, b) {
    final aTop = a.bounds.top;
    final bTop = b.bounds.top;
    // 4pt 以内の差は同一行とみなして左→右順にする
    if ((aTop - bTop).abs() > 4) {
      return bTop.compareTo(aTop); // 降順（上の要素が先）
    }
    return a.bounds.left.compareTo(b.bounds.left);
  });

  final buf = StringBuffer();
  for (final f in frags) {
    buf.write(f.text);
  }

  return buf.toString()
      // リガチャを基本文字に展開（合字が音声合成エンジンに渡ると読み飛ばされる場合がある）
      .replaceAll('ﬁ', 'fi')
      .replaceAll('ﬂ', 'fl')
      .replaceAll('ﬀ', 'ff')
      .replaceAll('ﬃ', 'ffi')
      .replaceAll('ﬄ', 'ffl')
      // 印刷用制御文字の除去（改行・タブ以外の非印刷可能文字）
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
      // 連続する空白・タブを1スペースに圧縮
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      // 3行以上の連続改行を2行に圧縮
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// テキストを読み上げ可能なチャンクに分割する。
///
/// iOS の AVSpeechSynthesizer は一度に処理できる文字数に上限があり、
/// 長文を渡すと途中で無音停止する。文末記号で区切ることで自然な区切りにする。
List<String> _buildTtsChunks(String text, {int maxLen = 2000}) {
  if (text.length <= maxLen) return [text];
  final chunks = <String>[];
  var start = 0;
  while (start < text.length) {
    var end = (start + maxLen).clamp(0, text.length);
    if (end < text.length) {
      // 文末記号（句点・感嘆符・疑問符・改行）で切ることで文中断を防ぐ
      final cut = text.lastIndexOf(RegExp(r'[。！？\n.!?]'), end);
      if (cut > start + maxLen ~/ 3) end = cut + 1;
    }
    final chunk = text.substring(start, end).trim();
    if (chunk.isNotEmpty) chunks.add(chunk);
    start = end;
  }
  return chunks.isEmpty ? [text] : chunks;
}

/// PDF ページを画像レンダリングして ML Kit OCR でテキストを抽出する。
/// テキスト層を持たない画像型 PDF に対するフォールバック処理。
/// ビューアーと独立した PdfDocument インスタンスを使うため render() が確実に動作する。
Future<String> _extractTextByOcr(
    String filePath, int pageIndex, String langCode) async {
  // ビューアーのdocとは別インスタンスでPDFを開く（render競合を回避）
  final doc = await PdfDocument.openFile(filePath);
  try {
    final page = doc.pages[pageIndex];
    // PDF は 72pt 基準。小さな日本語本文の認識には 432 DPI 相当の 6x でレンダリング
    const _kOcrScale = 6.0;
    final w = (page.width * _kOcrScale).toInt();
    final h = (page.height * _kOcrScale).toInt();
    debugPrint('[OCR] render size=$w x $h');
    final pdfImage = await page.render(width: w, height: h);
    debugPrint('[OCR] pdfImage=${pdfImage == null ? "null" : "${pdfImage.width}x${pdfImage.height}"}');
    if (pdfImage == null) return '';
    try {
      final uiImage = await pdfImage.createImage();
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.png);
      debugPrint('[OCR] byteData=${byteData == null ? "null" : "${byteData.lengthInBytes} bytes"}');
      if (byteData == null) return '';

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/tts_ocr_page.png');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());

      if (Platform.isIOS) {
        // ML Kit iOS は日本語 OCR 精度が低いため、Apple Vision Framework を使用する
        const _kVisionChannel = MethodChannel('app.tts.ocr');
        try {
          final text = await _kVisionChannel.invokeMethod<String>(
                'recognizeText',
                {'imagePath': tempFile.path},
              ) ??
              '';
          debugPrint('[OCR] Vision result length=${text.length}');
          return text;
        } catch (e) {
          debugPrint('[OCR] Vision error: $e');
          return '';
        }
      }

      // Android: ML Kit を使用
      final script = langCode == 'ja'
          ? TextRecognitionScript.japanese
          : TextRecognitionScript.latin;
      debugPrint('[OCR] using script=${langCode == 'ja' ? 'japanese' : 'latin'}');
      final recognizer = TextRecognizer(script: script);
      try {
        final result = await recognizer.processImage(
          InputImage.fromFilePath(tempFile.path),
        );
        debugPrint('[OCR] blocks=${result.blocks.length}');
        // ブロックを上から下の順に並べて結合
        final blocks = result.blocks
          ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
        return blocks.map((b) => b.text).join('\n');
      } finally {
        await recognizer.close();
      }
    } finally {
      pdfImage.dispose();
    }
  } finally {
    await doc.dispose();
  }
}
