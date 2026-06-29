import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../controllers/bookmark_controller.dart';
import '../../controllers/memo_controller.dart';
import '../../entities/search_match.dart';
import '../../l10n.dart';
import '../pdf_viewer/pdf_viewer_constants.dart';
import 'pdf_link_overlay.dart';
import 'pdf_search_highlight.dart';
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
  const PdfViewerPage({super.key, this.initialFilePath});

  /// コンテンツ一覧から遷移してきた場合のローカルファイルパス
  final String? initialFilePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ダークモードが有効かどうか（PDFページ色反転に使用）
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Scaffold の Key: ドロワーをコードから開閉するために必要
    final scaffoldKey = useMemoized(() => GlobalKey<ScaffoldState>());

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

    /// 指定ページ番号に移動する（PageView アニメーション付き）。
    void goToPage(int page) {
      currentPage.value = page;
      pageController.animateToPage(
        page - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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
                          itemCount: doc.pages.length,
                          onPageChanged: (index) {
                            currentPage.value = index + 1;
                            // ページ切り替え時にポインター数をリセット。
                            // 切り替えアニメーション中に pointer cancel が
                            // 届かない場合でも確実に 0 に戻す。
                            pointerCountNotifier.value = 0;
                          },
                          itemBuilder: (context, index) {
                            return InteractiveViewer(
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
                                maximumDpi: 300,
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
                            );
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
