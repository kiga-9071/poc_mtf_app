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
import '../../services/analytics_service.dart';
import '../../services/capture_protection_service.dart';
import '../../services/pdf_document_cache.dart';
import '../../services/pdf_preview_cache.dart';

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
    // doc==null（Pdfium初期化中）の間でもキャッシュ画像を即時表示するための先読み
    final initialPreview = useState<ui.Image?>(null);
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
    // 見開き分割モード（true のとき PDF の各ページを左右に分割して表示）
    final isSplitMode = useState(false);
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
    // TTS の speakText 内位置 → pageText.fullText 内位置マッピング
    final ttsFragMap = useState<List<({int speakOff, int origOff, int len})>>([]);
    // OCR パス用ハイライトデータ（normalizedRect は [0,1] 正規化座標、画像左上原点）
    final ttsOcrBlocks = useState<List<({String text, Rect normalizedRect})>>([]);
    // OCR 読み上げ中の現在ブロックインデックス（null = 非ハイライト）
    final ttsOcrHighlightIdx = useState<int?>(null);

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
        ttsFragMap.value = [];
        ttsOcrBlocks.value = [];
        ttsOcrHighlightIdx.value = null;
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
      if (initialFilePath == null) return null;
      selectedFile.value = File(initialFilePath!);

      // ファイル名をコンテンツIDとして使用（パスの最後のセグメント）
      final fileName = initialFilePath!.split('/').last;
      AnalyticsService.logPdfOpen(
        contentId: fileName,
        contentTitle: fileName,
      );

      // ── キャッシュ先読み ────────────────────────────────────────────────
      // PdfDocumentViewBuilder が doc を返すまで（Pdfium 初期化 = 数秒）、
      // ディスクキャッシュがあれば即座に表示してユーザーの空白待ちを解消する。
      var cancelled = false;
      final cachePath = PdfPreviewCache.cachePath(initialFilePath!, 0);
      File(cachePath).readAsBytes().then((bytes) async {
        if (cancelled) return;
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        if (!cancelled && context.mounted) {
          initialPreview.value = frame.image;
        } else {
          frame.image.dispose();
        }
      }).catchError((_) {});

      return () {
        cancelled = true;
        // アンマウント中に hook の setter を呼ぶと defunct element への
        // setState になるため、image の dispose のみ行う。
        initialPreview.value?.dispose();
      };
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

    // ファイルまたは分割モードが変わるたびに新しいコントローラーを生成してページ 0 にリセット
    final pageController = useMemoized(
      () => PageController(initialPage: 0),
      [selectedFile.value, isSplitMode.value],
    );

    // 分割モード切り替え時に現在ページを 1 にリセット
    useEffect(() {
      currentPage.value = 1;
      return null;
    }, [isSplitMode.value]);

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
        ttsFragMap.value = [];
        ttsOcrBlocks.value = [];
        ttsOcrHighlightIdx.value = null;
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
        ttsOcrBlocks.value = [];
        ttsOcrHighlightIdx.value = null;
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
          final (extractedText, fragMap) = _buildTtsTextWithMap(pageText);
          speakText = extractedText;
          ttsFragMap.value = fragMap;
        } else {
          // テキスト層なし → OCR でテキストと座標を同時に取得する。
          // PDFKit はテキストを返すが座標（バウンディングボックス）を持たないため、
          // progressHandler でハイライト位置を特定できない（iOS 固有の不具合）。
          // OCR（iOS: Vision Framework）はテキストと座標の両方を返すため常に利用する。
          usedOcr = true;
          speakText = '';
          final filePath = selectedFile.value?.path;
          if (filePath != null) {
            final ocrResult = await _extractTextByOcr(filePath, currentPage.value - 1, langCode);
            speakText = ocrResult.text;
            ttsOcrBlocks.value = ocrResult.blocks;
            debugPrint('[TTS] OCR result length=${speakText.length}, blocks=${ocrResult.blocks.length}');
          }
          // OCR でもテキストが取得できない場合、iOS では PDFKit を最終手段として試みる
          // （この場合はハイライトなしで読み上げのみ）
          if (speakText.isEmpty && Platform.isIOS) {
            final filePath = selectedFile.value?.path;
            if (filePath != null) {
              const _kPdfChannel = MethodChannel('app.tts.pdf');
              try {
                final pdfKitText = await _kPdfChannel.invokeMethod<String>(
                      'extractText',
                      {'filePath': filePath, 'pageIndex': currentPage.value - 1},
                    ) ?? '';
                debugPrint('[TTS] PDFKit fallback length=${pdfKitText.length}');
                if (pdfKitText.trim().isNotEmpty) {
                  speakText = pdfKitText.trim();
                  usedOcr = false;
                }
              } catch (e) {
                debugPrint('[TTS] PDFKit error: $e');
              }
            }
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
            final ocrResult = await _extractTextByOcr(
                filePath, currentPage.value - 1, langCode);
            debugPrint('[TTS] OCR fallback length=${ocrResult.text.length}, blocks=${ocrResult.blocks.length}');
            if (ocrResult.text.isNotEmpty) {
              speakText = ocrResult.text;
              usedOcr = true;
              ttsPageText.value = null;
              ttsFragMap.value = [];
              ttsOcrBlocks.value = ocrResult.blocks;
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
            tts.speak(chunks[chunkIndex].text);
          } else {
            ttsStatus.value = TtsStatus.idle;
            ttsHighlightStart.value = null;
            ttsHighlightEnd.value = null;
            ttsPageText.value = null;
            ttsFragMap.value = [];
            ttsOcrBlocks.value = [];
            ttsOcrHighlightIdx.value = null;
          }
        });

        tts.setProgressHandler((text, start, end, word) {
          if (!context.mounted) return;

          // ── ネイティブテキストパス ─────────────────────────────────────────
          if (ttsPageText.value != null) {
            final fm = ttsFragMap.value;
            if (fm.isEmpty) return;
            final pt = ttsPageText.value!;
            final searchWord = word.trim();
            if (searchWord.isEmpty) return;
            final speakPos = chunks[chunkIndex].start + start;
            final approxPos = _mapSpeakToOrig(fm, speakPos);
            final searchFrom = (approxPos - 150).clamp(0, pt.fullText.length);
            int idx = pt.fullText.indexOf(searchWord, searchFrom);
            if (idx < 0) idx = pt.fullText.indexOf(searchWord);
            debugPrint('[TTS highlight] word="$searchWord" approxPos=$approxPos idx=$idx');
            if (idx >= 0) {
              ttsHighlightStart.value = idx;
              ttsHighlightEnd.value   = idx + searchWord.length;
            }
            return;
          }

          // ── OCR パス: OCR ブロックのバウンディングボックスでハイライト ────────
          final blocks = ttsOcrBlocks.value;
          if (blocks.isEmpty) return;
          final speakPos = chunks[chunkIndex].start + start;
          var pos = 0;
          for (var i = 0; i < blocks.length; i++) {
            final blockEnd = pos + blocks[i].text.length;
            if (speakPos >= pos && speakPos < blockEnd) {
              debugPrint('[TTS OCR highlight] block=$i word="$word" speakPos=$speakPos');
              ttsOcrHighlightIdx.value = i;
              break;
            }
            pos += blocks[i].text.length + 1; // '\n' セパレータ分
          }
        });

        ttsStatus.value = TtsStatus.speaking;
        await tts.speak(chunks[0].text);
      } catch (e, st) {
        debugPrint('[TTS] error: $e\n$st');
        ttsStatus.value = TtsStatus.idle;
        ttsPageText.value = null;
        ttsOcrBlocks.value = [];
        ttsOcrHighlightIdx.value = null;
      }
    }

    // goToPage によるプログラム遷移中フラグ。
    // animateToPage が経由ページで onPageChanged を発火させ currentPage を
    // 上書きするのを防ぐために使用する。
    final isProgrammaticNav = useRef(false);

    /// 指定 PDF ページ番号に移動する（PageView アニメーション付き）。
    /// 分割モードでは左半分（偶数仮想ページ）へ移動する。
    void goToPage(int pdfPage) {
      isProgrammaticNav.value = true;
      currentPage.value = pdfPage;
      final virtualIndex =
          isSplitMode.value ? (pdfPage - 1) * 2 : pdfPage - 1;
      pageController
          .animateToPage(
            virtualIndex,
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
                    child: Builder(builder: (context) {
                    // キャッシュ済みドキュメントがあれば PdfDocumentRefDirect で即時表示、
                    // なければ通常の PdfDocumentRefFile でロードする。
                    final filePath = selectedFile.value!.path;
                    final cachedDoc = PdfDocumentCache.get(filePath);
                    final docRef = cachedDoc != null
                        ? PdfDocumentRefDirect(cachedDoc, autoDispose: false)
                        : PdfDocumentRefFile(filePath);
                    return PdfDocumentViewBuilder(
                      key: ValueKey(filePath),
                      documentRef: docRef,
                      builder: (context, doc) {
                        if (doc == null) {
                          // キャッシュ先読み済みなら即座に表示、なければスピナー
                          final preview = initialPreview.value;
                          if (preview != null) {
                            return Center(
                                child: RawImage(
                                    image: preview, fit: BoxFit.contain));
                          }
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
                            // ── フェーズ1: ドキュメントオープン完了 ──────────────
                            debugPrint(
                                '[PDF Phase1] ドキュメントオープン: ${(ms / 1000).toStringAsFixed(2)}秒');
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
                          itemCount: isSplitMode.value
                              ? doc.pages.length * 2
                              : doc.pages.length,
                          onPageChanged: (index) {
                            // プログラム遷移中は経由ページによる上書きを無視する
                            if (!isProgrammaticNav.value) {
                              final page = isSplitMode.value
                                  ? index ~/ 2 + 1
                                  : index + 1;
                              currentPage.value = page;
                              final filePath = selectedFile.value?.path;
                              if (filePath != null) {
                                AnalyticsService.logPdfPageView(
                                  contentId: filePath.split('/').last,
                                  pageNumber: page,
                                );
                              }
                            }
                            // ページ切り替え時にポインター数をリセット。
                            // 切り替えアニメーション中に pointer cancel が
                            // 届かない場合でも確実に 0 に戻す。
                            pointerCountNotifier.value = 0;
                          },
                          itemBuilder: (context, index) {
                            // 分割モード: 仮想ページ index を PDF ページと左右半分に分解する
                            final pdfIndex =
                                isSplitMode.value ? index ~/ 2 : index;
                            final showRight =
                                isSplitMode.value && index.isOdd;

                            // 分割モード: PdfPageView を画面2倍幅のコンテナで
                            // レンダリングし、左右いずれかの半分だけを表示する。
                            // decorationBuilder 内でクリップすると pageImage が
                            // 正しくスケールしないため、外側でラップする方式をとる。
                            final gesture = GestureDetector(
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
                                pageNumber: pdfIndex + 1,
                                // 分割モードは OverflowBox で2倍幅レンダリングになるため
                                // 96 DPI に抑えて約2倍の高速化を図る（通常モードは
                                // ウィジェットサイズで制限されるため変化なし）。
                                maximumDpi: isSplitMode.value ? 96 : 150,
                                backgroundColor:
                                    isDark ? Colors.black : Colors.white,
                                // decorationBuilder: ページ画像の上にオーバーレイを重ねる
                                decorationBuilder:
                                    (ctx, pageSize, page, pageImage) {
                                  // ── フェーズ2: ページ描画完了ログ ──────────────────
                                  if (pageImage != null && page.pageNumber == 1) {
                                    final ms = DateTime.now()
                                        .difference(viewerOpenedAt)
                                        .inMilliseconds;
                                    debugPrint(
                                        '[PDF Phase2] ページ1描画完了: ${(ms / 1000).toStringAsFixed(2)}秒');
                                  }
                                  // 診断: decorationBuilder の pageSize と PDF ネイティブサイズ
                                  if (page.pageNumber == currentPage.value &&
                                      ttsOcrBlocks.value.isNotEmpty) {
                                    debugPrint('[DECOR_SIZE] pageSize=${pageSize.width.toStringAsFixed(1)}x${pageSize.height.toStringAsFixed(1)} '
                                        'page.native=${page.width.toStringAsFixed(1)}x${page.height.toStringAsFixed(1)}');
                                  }

                                  // ダークモード時: ページ画像に色反転フィルターを適用
                                  Widget? image = pageImage;
                                  if (isDark && image != null) {
                                    image = ColorFiltered(
                                      colorFilter: kPdfInvertColorFilter,
                                      child: image,
                                    );
                                  }

                                  // ── 通常モード ───────────────────────────────────
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
                                              // pageImage が null の間（レンダリング中）は
                                              // 低解像度プレビューを表示してUXを改善する。
                                              // プレビューは 400px 幅で高速レンダリングし、
                                              // フル品質が届いたら自動的に置き換わる。
                                              if (image != null)
                                                image
                                              else
                                                _PagePreview(
                                                  page: page,
                                                  pdfPath: selectedFile.value?.path ?? '',
                                                  isDark: isDark,
                                                ),
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
                                              // TTS 読み上げ中の現在単語ハイライト（ネイティブテキストパス）
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
                                              // TTS 読み上げ中の現在行ハイライト（OCR パス）
                                              // normalizedRect（[0,1]）を size にスケールして配置。
                                              if (ttsOcrHighlightIdx.value != null &&
                                                  ttsOcrBlocks.value.isNotEmpty &&
                                                  page.pageNumber == currentPage.value)
                                                Builder(builder: (_) {
                                                  final idx = ttsOcrHighlightIdx.value!;
                                                  if (idx >= ttsOcrBlocks.value.length) {
                                                    return const SizedBox.shrink();
                                                  }
                                                  final r = ttsOcrBlocks.value[idx].normalizedRect;
                                                  final markerLeft = r.left * size.width;
                                                  final markerTop = r.top * size.height;
                                                  // OCR バウンディングボックスは文字のコア部分のみを含むため
                                                  // 高さが極端に小さくなる場合がある。視認性のため最低高を確保する。
                                                  final markerW = ((r.right - r.left) * size.width).clamp(10.0, size.width);
                                                  final rawH = (r.bottom - r.top) * size.height;
                                                  // OCR の bbox は文字コア部分のみのため高さが小さい。最低 12px を保証する。
                                                  final markerH = rawH.clamp(12.0, size.height * 0.12);
                                                  debugPrint('[TTS OCR overlay] idx=$idx '
                                                      'normRect=(${r.left.toStringAsFixed(3)},'
                                                      '${r.top.toStringAsFixed(3)},'
                                                      '${r.right.toStringAsFixed(3)},'
                                                      '${r.bottom.toStringAsFixed(3)}) '
                                                      'px=(${markerLeft.toStringAsFixed(1)},'
                                                      '${markerTop.toStringAsFixed(1)},'
                                                      '${markerW.toStringAsFixed(1)}x${markerH.toStringAsFixed(1)}) '
                                                      'size=${size.width.toInt()}x${size.height.toInt()}');
                                                  return Stack(children: [
                                                    Positioned(
                                                      left: markerLeft,
                                                      top: markerTop,
                                                      width: markerW,
                                                      height: markerH,
                                                      child: Container(
                                                        color: Colors.yellow.withValues(alpha: 0.5),
                                                      ),
                                                    ),
                                                  ]);
                                                }),
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
                            );   // gesture (GestureDetector)

                            if (!isSplitMode.value) return gesture;

                            // 分割モード: 画面幅の2倍コンテナでレンダリングし
                            // 左半分または右半分だけを ClipRect で切り出す。
                            return LayoutBuilder(
                              builder: (ctx, constraints) {
                                final sw = constraints.maxWidth;
                                final sh = constraints.maxHeight;
                                return ClipRect(
                                  child: OverflowBox(
                                    alignment: showRight
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    maxWidth: sw * 2,
                                    maxHeight: sh,
                                    child: SizedBox(
                                      width: sw * 2,
                                      child: gesture,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),   // PageView.builder
                          ),   // ValueListenableBuilder<int>
                          ),   // ValueListenableBuilder<bool>
                        );   // Listener
                      },
                    );    // PdfDocumentViewBuilder (return stmt)
                    }),   // Builder
                  ),      // SelectionArea
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
                onBack: () {
                  final filePath = selectedFile.value?.path;
                  if (filePath != null) {
                    AnalyticsService.logPdfClose(
                      contentId: filePath.split('/').last,
                      lastPage: currentPage.value,
                    );
                  }
                  context.canPop() ? context.pop() : context.go('/');
                },
                ttsStatus: ttsStatus.value,
                onTtsTap: toggleTts,
                isSplitMode: isSplitMode.value,
                onSplitToggle: selectedFile.value != null
                    ? () => isSplitMode.value = !isSplitMode.value
                    : null,
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

/// PDFページのレンダリング完了前に表示するプレビューウィジェット。
///
/// 表示優先度：
/// 1. ディスクキャッシュ（2回目以降は < 100ms で表示）
/// 2. 400px 幅のオンデマンドレンダリング（初回のみ 1〜3 秒）
///
/// レンダリング後は PNG をディスクに保存し次回起動時も即座に表示できる。
/// フル品質の [pageImage] が届くと親の `decorationBuilder` 側でこのウィジェットが
/// ツリーから外れ、`dispose()` で `ui.Image` を解放する。
class _PagePreview extends StatefulWidget {
  const _PagePreview({
    required this.page,
    required this.pdfPath,
    required this.isDark,
  });

  final PdfPage page;
  /// キャッシュファイルの生成に使うPDFのローカルパス。空文字の場合はキャッシュをスキップ。
  final String pdfPath;
  final bool isDark;

  @override
  State<_PagePreview> createState() => _PagePreviewState();
}

class _PagePreviewState extends State<_PagePreview> {
  ui.Image? _preview;

  @override
  void initState() {
    super.initState();
    _renderPreview();
  }

  @override
  void didUpdateWidget(_PagePreview old) {
    super.didUpdateWidget(old);
    if (old.page.pageNumber != widget.page.pageNumber ||
        old.pdfPath != widget.pdfPath) {
      _preview?.dispose();
      setState(() => _preview = null);
      _renderPreview();
    }
  }

  String get _cachePath =>
      PdfPreviewCache.cachePath(widget.pdfPath, widget.page.pageNumber - 1);

  Future<void> _renderPreview() async {
    final t0 = DateTime.now();
    final label = 'p${widget.page.pageNumber}';

    // ── 1. ディスクキャッシュ確認（2回目以降は < 100ms）─────────────────────
    if (widget.pdfPath.isNotEmpty) {
      try {
        final cacheFile = File(_cachePath);
        if (await cacheFile.exists()) {
          final bytes = await cacheFile.readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          if (mounted) setState(() => _preview = frame.image);
          debugPrint('[PDF Preview] $label キャッシュヒット: ${DateTime.now().difference(t0).inMilliseconds}ms');
          return;
        }
      } catch (_) {}
    }

    // ── 2. ネイティブサムネイル API（iOS: PDFPage.thumbnail / Android: PdfRenderer）
    if (widget.pdfPath.isNotEmpty) {
      debugPrint('[PDF Preview] $label ネイティブThumbnail呼び出し開始');
      final nativeBytes = await PdfPreviewCache.fetchNativeThumbnail(
        widget.pdfPath, widget.page.pageNumber - 1);
      if (nativeBytes != null) {
        try {
          final codec = await ui.instantiateImageCodec(nativeBytes);
          final frame = await codec.getNextFrame();
          final img = frame.image;
          if (mounted) setState(() => _preview = img);
          debugPrint('[PDF Preview] $label ネイティブThumbnail完了: ${DateTime.now().difference(t0).inMilliseconds}ms (${nativeBytes.length}bytes)');
          File(_cachePath).writeAsBytes(nativeBytes).catchError((_) => File(_cachePath));
          return;
        } catch (_) {}
      } else {
        debugPrint('[PDF Preview] $label ネイティブThumbnailがnullを返した（失敗）');
      }
    }

    // ── 3. pdfrx レンダリング（フォールバック）─────────────────────────────
    debugPrint('[PDF Preview] $label pdfrx render開始');
    final page = widget.page;
    const previewWidth = 400;
    final previewHeight = (previewWidth * page.height / page.width).toInt();
    try {
      final pdfImg = await page.render(width: previewWidth, height: previewHeight);
      if (pdfImg == null) return;
      final img = await pdfImg.createImage();
      pdfImg.dispose();
      if (mounted) {
        setState(() => _preview = img);
      } else {
        img.dispose();
        return;
      }
      debugPrint('[PDF Preview] $label pdfrx render完了: ${DateTime.now().difference(t0).inMilliseconds}ms');
      if (widget.pdfPath.isNotEmpty) _saveImageToCache(img, _cachePath);
    } catch (e) {
      debugPrint('[PDF Preview] $label pdfrx render失敗: $e');
    }
  }

  static Future<void> _saveImageToCache(ui.Image img, String path) async {
    try {
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        await File(path).writeAsBytes(byteData.buffer.asUint8List());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    if (preview == null) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: widget.isDark ? Colors.white38 : Colors.black26,
        ),
      );
    }
    return SizedBox.expand(
      child: RawImage(image: preview, fit: BoxFit.contain),
    );
  }
}

/// PDFのテキストフラグメントを視覚的な読み順（上→下・左→右）にソートしてテキストと
/// ハイライト用位置マッピングを同時に構築する。
///
/// 返り値: (speakText, fragMap)
/// fragMap の各エントリは「ソート後テキスト内オフセット speakOff → pageText.fullText
/// 内オフセット origOff、長さ len」のマッピング。
/// setProgressHandler が返す文字位置 (speakText 内) を _mapSpeakToOrig で
/// pageText.fullText 内位置に変換することで正確なハイライト座標が得られる。
(String, List<({int speakOff, int origOff, int len})>) _buildTtsTextWithMap(
    PdfPageText pageText) {
  // 各フラグメントの pageText.fullText 内の開始位置を計算
  final origOffsets = <int>[];
  var off = 0;
  for (final f in pageText.fragments) {
    origOffsets.add(off);
    off += f.text.length;
  }

  // フラグメントを視覚的な読み順（PDF 座標系: top 降順 → left 昇順）でソート
  final sortedIdx = List.generate(pageText.fragments.length, (i) => i);
  sortedIdx.sort((i, j) {
    final aTop = pageText.fragments[i].bounds.top;
    final bTop = pageText.fragments[j].bounds.top;
    if ((aTop - bTop).abs() > 4) return bTop.compareTo(aTop);
    return pageText.fragments[i].bounds.left
        .compareTo(pageText.fragments[j].bounds.left);
  });

  // ソート後テキストを構築しつつ、フラグメントごとの位置マッピングを記録
  final buf = StringBuffer();
  final fragMap = <({int speakOff, int origOff, int len})>[];
  var speakOff = 0;
  for (final i in sortedIdx) {
    final frag = pageText.fragments[i];
    fragMap.add((speakOff: speakOff, origOff: origOffsets[i], len: frag.text.length));
    buf.write(frag.text);
    speakOff += frag.text.length;
  }

  final speakText = buf.toString()
      .replaceAll('ﬁ', 'fi')
      .replaceAll('ﬂ', 'fl')
      .replaceAll('ﬀ', 'ff')
      .replaceAll('ﬃ', 'ffi')
      .replaceAll('ﬄ', 'ffl')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  return (speakText, fragMap);
}

/// speakText 内の文字位置を pageText.fullText 内の文字位置に変換する。
/// fragMap は _buildTtsTextWithMap が返すマッピングリスト（speakOff 昇順ソート済み）。
int _mapSpeakToOrig(
    List<({int speakOff, int origOff, int len})> fragMap, int speakPos) {
  if (fragMap.isEmpty || speakPos < 0) return 0;
  var lo = 0;
  var hi = fragMap.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (fragMap[mid].speakOff <= speakPos) { lo = mid; } else { hi = mid - 1; }
  }
  final entry = fragMap[lo];
  return entry.origOff + (speakPos - entry.speakOff).clamp(0, entry.len);
}

/// テキストを読み上げ可能なチャンクに分割する。
/// 各チャンクの speakText 内での開始位置も返す（全チャンクでのハイライト対応に必要）。
///
/// iOS の AVSpeechSynthesizer は一度に処理できる文字数に上限があり、
/// 長文を渡すと途中で無音停止する。文末記号で区切ることで自然な区切りにする。
List<({String text, int start})> _buildTtsChunks(String text, {int maxLen = 2000}) {
  if (text.length <= maxLen) return [(text: text, start: 0)];
  final chunks = <({String text, int start})>[];
  var pos = 0;
  while (pos < text.length) {
    var end = (pos + maxLen).clamp(0, text.length);
    if (end < text.length) {
      final cut = text.lastIndexOf(RegExp(r'[。！？\n.!?]'), end);
      if (cut > pos + maxLen ~/ 3) end = cut + 1;
    }
    final chunk = text.substring(pos, end).trim();
    if (chunk.isNotEmpty) chunks.add((text: chunk, start: pos));
    pos = end;
  }
  return chunks.isEmpty ? [(text: text, start: 0)] : chunks;
}

/// PDF ページを画像レンダリングして ML Kit OCR でテキストを抽出する。
/// テキスト層を持たない画像型 PDF に対するフォールバック処理。
/// ビューアーと独立した PdfDocument インスタンスを使うため render() が確実に動作する。
///
/// 返値: ({text, blocks})
///   blocks.normalizedRect は OCR 画像に対する [0,1] 正規化座標（左上原点）。
///   pdfrx の render() はラスター画像として Y=0 を上端で出力するため、
///   Flutter の画面座標系と同じ向きになり、そのままスケールして配置できる。
Future<({String text, List<({String text, Rect normalizedRect})> blocks})>
    _extractTextByOcr(String filePath, int pageIndex, String langCode) async {
  const _empty = (text: '', blocks: <({String text, Rect normalizedRect})>[]);

  // ビューアーのdocとは別インスタンスでPDFを開く（render競合を回避）
  final doc = await PdfDocument.openFile(filePath);
  try {
    final page = doc.pages[pageIndex];
    // PDF は 72pt 基準。小さな日本語本文の認識には 432 DPI 相当の 6x でレンダリング
    const _kOcrScale = 6.0;
    final w = (page.width * _kOcrScale).toInt();
    final h = (page.height * _kOcrScale).toInt();
    debugPrint('[OCR] render size=${w}x${h}, page=${page.width.toStringAsFixed(1)}x${page.height.toStringAsFixed(1)}pt');
    // fullWidth/fullHeight を明示することで PDF コンテンツが w×h ピクセル全体に
    // レンダリングされる。省略すると pdfrx が page.width (72DPI=595pt) をデフォルトとして
    // 使用し、コンテンツが左上の 595×842 領域にのみ描画されてしまう。
    final pdfImage = await page.render(fullWidth: w.toDouble(), fullHeight: h.toDouble());
    debugPrint('[OCR] pdfImage=${pdfImage == null ? "null" : "${pdfImage.width}x${pdfImage.height}"}');
    if (pdfImage == null) return _empty;
    // w/h（fullWidth/fullHeight として渡した値）で正規化する。
    try {
      final uiImage = await pdfImage.createImage();
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.png);
      debugPrint('[OCR] byteData=${byteData == null ? "null" : "${byteData.lengthInBytes} bytes"}');
      if (byteData == null) return _empty;

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/tts_ocr_page.png');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());

      if (Platform.isIOS) {
        // ML Kit iOS は日本語 OCR 精度が低いため、Apple Vision Framework を使用する。
        // AppDelegate.recognizeText が [{text, left, top, right, bottom}] を返す。
        // Swift 側で Y 反転済み（左上原点、[0,1] 正規化座標）なのでそのまま使用。
        const _kVisionChannel = MethodChannel('app.tts.ocr');
        try {
          final rawBlocks = await _kVisionChannel.invokeMethod<List>(
            'recognizeText',
            {'imagePath': tempFile.path},
          );
          if (rawBlocks == null || rawBlocks.isEmpty) return _empty;
          final ocrBlocks = rawBlocks.cast<Map>().map((m) {
            final blockText = m['text'] as String? ?? '';
            // Swift からは Flutter 慣行の正規化座標（左上原点 [0,1]）で届く
            final rect = Rect.fromLTRB(
              (m['left']   as num? ?? 0).toDouble(),
              (m['top']    as num? ?? 0).toDouble(),
              (m['right']  as num? ?? 0).toDouble(),
              (m['bottom'] as num? ?? 0).toDouble(),
            );
            return (text: blockText, normalizedRect: rect);
          }).toList();
          final joinedText = ocrBlocks.map((b) => b.text).join('\n');
          debugPrint('[OCR] Vision lines=${ocrBlocks.length}, text=${joinedText.length}chars');
          return (text: joinedText, blocks: ocrBlocks);
        } catch (e) {
          debugPrint('[OCR] Vision error: $e');
          return _empty;
        }
      }

      // Android: ML Kit を使用。TextLine（行単位）でハイライト精度を向上。
      // render() はラスター座標系（Y=0 が上端）で出力するため、
      // 正規化した値をそのまま Flutter 座標に適用できる（Y 反転不要）。
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
        // TextBlock を上から下にソートし、各 TextLine を行単位でリスト化
        final sortedBlocks = result.blocks
          ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
        final ocrBlocks = <({String text, Rect normalizedRect})>[];
        for (final block in sortedBlocks) {
          final sortedLines = block.lines
            ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
          for (final line in sortedLines) {
            final bb = line.boundingBox;
            // 画像ピクセル座標を [0,1] に正規化（render() に渡した w/h で割る）
            final rect = Rect.fromLTRB(
              bb.left   / w,
              bb.top    / h,
              bb.right  / w,
              bb.bottom / h,
            );
            ocrBlocks.add((text: line.text, normalizedRect: rect));
            debugPrint('[OCR] line="${line.text.substring(0, line.text.length.clamp(0, 20))}" '
                'norm=(${rect.left.toStringAsFixed(3)},${rect.top.toStringAsFixed(3)},'
                '${rect.right.toStringAsFixed(3)},${rect.bottom.toStringAsFixed(3)})');
          }
        }
        final joinedText = ocrBlocks.map((b) => b.text).join('\n');
        debugPrint('[OCR] lines=${ocrBlocks.length}, text=${joinedText.length}chars');
        return (text: joinedText, blocks: ocrBlocks);
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
