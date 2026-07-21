import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../services/pdf_preview_cache.dart';
import 'pdf_viewer_constants.dart';

// スクロール方向に事前レンダリングするウィジェット領域（px）
// 大きすぎると初期表示時に多数のページが同時レンダリングキューに積まれ、
// 現在ページ付近のサムネイル表示が遅延する原因になる。
// ignore: deprecated_member_use
const _kCacheExtent = 200.0;

/// 画面下部に表示するページサムネイルのストリップ。
/// 横スクロール可能で、現在ページを赤枠でハイライト表示する。
/// ブックマーク済みページにはしおりアイコンを表示する。
/// ダークモード時はサムネイルにも色反転フィルターを適用する。
class PdfThumbnailStrip extends StatelessWidget {
  const PdfThumbnailStrip({
    super.key,
    required this.filePath,
    required this.pageCount,
    required this.currentPage,
    required this.bookmarks,
    required this.scrollController,
    required this.onPageTap,
  });

  /// PDFのローカルファイルパス（サムネイル生成用）
  final String filePath;

  /// 総ページ数（0 = ロード中）
  final int pageCount;

  /// 現在ページ番号（赤枠ハイライトに使用）
  final int currentPage;

  /// ブックマーク済みページ番号のセット
  final Set<int> bookmarks;

  /// 横スクロールの制御コントローラー（親から受け取り自動スクロールに使用）
  final ScrollController scrollController;

  /// サムネイルタップ時のコールバック（タップしたページ番号を渡す）
  final ValueChanged<int> onPageTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: kPdfThumbnailHeight + 32,
      color: Colors.grey[850],
      child: pageCount == 0
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white54),
              ),
            )
          : PdfDocumentViewBuilder.file(
              filePath,
              builder: (context, document) {
                return ListView.builder(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  // ignore: deprecated_member_use
                  cacheExtent: _kCacheExtent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  itemCount: pageCount,
                  itemBuilder: (context, index) {
                    final pageNum = index + 1;
                    final isSelected = pageNum == currentPage;
                    final isBookmarked = bookmarks.contains(pageNum);

                    return GestureDetector(
                      onTap: () => onPageTap(pageNum),
                      child: Container(
                        width: kPdfThumbnailWidth,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected
                                ? kPdfRedPrimary
                                : Colors.transparent,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // キャッシュ付きサムネイル（一度レンダリングした画像を保持）
                                  _CachedThumbnail(
                                    filePath: filePath,
                                    document: document,
                                    pageNumber: pageNum,
                                    isDark: isDark,
                                  ),
                                  if (isBookmarked)
                                    const Positioned(
                                      top: 2,
                                      right: 2,
                                      child: Icon(Icons.bookmark,
                                          color: Colors.amber, size: 14),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              color: Colors.black54,
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '$pageNum',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected
                                      ? Colors.red[200]
                                      : Colors.white,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

/// レンダリング済み画像を静的キャッシュに保持するサムネイルウィジェット。
/// ListView でスクロールアウトして dispose されても画像が失われないため、
/// 再表示時に白フラッシュが発生しない。
///
/// レンダリング優先度:
///   1. インメモリキャッシュ（即時）
///   2. ディスクキャッシュ（< 100ms）
///   3. ネイティブサムネイル API（iOS: PDFKit。組み込みサムネイルで瞬時）
///   4. pdfrx フォールバック（Android / ネイティブ失敗時）
class _CachedThumbnail extends StatefulWidget {
  const _CachedThumbnail({
    required this.filePath,
    required this.document,
    required this.pageNumber,
    required this.isDark,
  });

  final String filePath;
  final PdfDocument? document;
  final int pageNumber;
  final bool isDark;

  @override
  State<_CachedThumbnail> createState() => _CachedThumbnailState();
}

class _CachedThumbnailState extends State<_CachedThumbnail> {
  // filePath + ページ番号をキーにする静的キャッシュ。
  // document?.sourceName ではなく filePath を使うことで document が null でも
  // 安定したキャッシュキーを保てる。dispose されても画像が残るため再スクロール時に即座に表示できる。
  static final Map<String, ui.Image> _cache = {};

  // 同時レンダリング数の上限。Pdfium は内部でシリアル処理するため、
  // 多数の render() を同時発行すると後続ページが長時間待たされる。
  // ネイティブ API も PDFDocument を毎回開くため制限が有効。
  static const int _maxConcurrentRenders = 2;
  static int _activeRenders = 0;
  static final List<Completer<void>> _waitQueue = [];

  ui.Image? _image;
  bool _rendering = false;

  String get _key => '${widget.filePath}_${widget.pageNumber}';

  @override
  void initState() {
    super.initState();
    _loadFromCacheOrRender();
  }

  @override
  void didUpdateWidget(_CachedThumbnail old) {
    super.didUpdateWidget(old);
    if (old.filePath != widget.filePath ||
        old.pageNumber != widget.pageNumber) {
      _loadFromCacheOrRender();
    }
  }

  void _loadFromCacheOrRender() {
    final cached = _cache[_key];
    if (cached != null) {
      _image = cached;
      return;
    }
    // document が null でもネイティブ API / ディスクキャッシュで対応できるため常に試みる
    if (!_rendering) {
      _render();
    }
  }

  // レンダースロットを解放し、待機中のウィジェットがあればスロットを引き継がせる。
  static void _releaseSlot() {
    if (_waitQueue.isNotEmpty) {
      // スロットを次の待機者に移譲（_activeRenders は変えない）
      _waitQueue.removeAt(0).complete();
    } else {
      _activeRenders--;
    }
  }

  Future<void> _render() async {
    _rendering = true;
    final pageIndex = widget.pageNumber - 1;
    final cachePath =
        PdfPreviewCache.stripCachePath(widget.filePath, pageIndex);

    // 1. ディスクキャッシュ（セマフォ不要、2回目以降はほぼ即時）
    try {
      final file = File(cachePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        _cache[_key] = frame.image;
        if (mounted) setState(() => _image = frame.image);
        _rendering = false;
        return; // セマフォを取得していないためここで終了
      }
    } catch (_) {}

    // 2. セマフォ取得（ネイティブ API / pdfrx の同時実行を制限）
    if (_activeRenders >= _maxConcurrentRenders) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
      // 待機中にウィジェットが dispose された場合はスキップしてスロットを返す
      if (!mounted) {
        _rendering = false;
        _releaseSlot();
        return;
      }
      // スロットは releaser から移譲済みなので _activeRenders は変えない
    } else {
      _activeRenders++;
    }

    try {
      // 3. ネイティブサムネイル（iOS: PDFKit）
      // 雑誌等の組み込みサムネイル付き PDF では瞬時に返る。
      // ストリップ用に @2x サイズ（140px）でリクエストし帯域を節約する。
      final nativeBytes = await PdfPreviewCache.fetchNativeThumbnail(
          widget.filePath, pageIndex,
          width: kPdfThumbnailWidth * 2);
      if (nativeBytes != null) {
        final codec = await ui.instantiateImageCodec(nativeBytes);
        final frame = await codec.getNextFrame();
        _cache[_key] = frame.image;
        if (mounted) setState(() => _image = frame.image);
        // fire-and-forget でディスクに保存（次回はディスクキャッシュから即時ロード）
        // ignore: unawaited_futures
        File(cachePath).writeAsBytes(nativeBytes);
        return;
      }

      // 4. pdfrx フォールバック（Android / ネイティブ API 失敗時）
      final doc = widget.document;
      if (doc == null) return;
      if (pageIndex < 0 || pageIndex >= doc.pages.length) return;
      final page = doc.pages[pageIndex];
      final w = kPdfThumbnailWidth.toInt();
      final h = (w * page.height / page.width).ceil();
      // fullWidth/fullHeight でページ全体を縮小レンダリング
      final pdfImg = await page.render(
        fullWidth: w.toDouble(),
        fullHeight: h.toDouble(),
      );
      if (pdfImg == null) return;
      final img = await pdfImg.createImage();
      pdfImg.dispose();
      _cache[_key] = img;
      if (mounted) setState(() => _image = img);
      // ignore: unawaited_futures
      _saveImageToDisk(img, cachePath);
    } catch (e) {
      debugPrint('[_CachedThumbnail] render failed p${widget.pageNumber}: $e');
    } finally {
      _rendering = false;
      _releaseSlot();
    }
  }

  // pdfrx でレンダリングした ui.Image を PNG としてディスクに保存する。
  static Future<void> _saveImageToDisk(ui.Image img, String path) async {
    try {
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        await File(path).writeAsBytes(byteData.buffer.asUint8List());
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null) {
      return ColoredBox(color: Colors.grey[700]!);
    }
    // 白背景を敷くことで BoxFit.contain の余白部分が黒くなるのを防ぐ。
    // ダークモード時は kPdfInvertColorFilter が白→黒に反転するため自然な見た目になる。
    Widget w = ColoredBox(
      color: Colors.white,
      child: SizedBox.expand(
        child: RawImage(image: img, fit: BoxFit.contain),
      ),
    );
    if (widget.isDark) {
      w = ColorFiltered(colorFilter: kPdfInvertColorFilter, child: w);
    }
    return w;
  }
}
