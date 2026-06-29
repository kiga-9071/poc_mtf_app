import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_viewer_constants.dart';

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
    // ダークモード時はサムネイルにも色反転フィルターを適用
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  itemCount: pageCount,
                  itemBuilder: (context, index) {
                    final pageNum = index + 1;
                    final isSelected = pageNum == currentPage;
                    final isBookmarked = bookmarks.contains(pageNum);

                    // サムネイルのPDFページビュー
                    Widget thumbnailPage = PdfPageView(
                      document: document,
                      pageNumber: pageNum,
                      maximumDpi: 72, // サムネイルは低解像度で十分
                      backgroundColor:
                          isDark ? Colors.black : Colors.white,
                    );
                    // ダークモード時: 色反転フィルターを適用
                    if (isDark) {
                      thumbnailPage = ColorFiltered(
                        colorFilter: kPdfInvertColorFilter,
                        child: thumbnailPage,
                      );
                    }

                    return GestureDetector(
                      onTap: () => onPageTap(pageNum),
                      child: Container(
                        width: kPdfThumbnailWidth,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          // 現在ページを赤枠でハイライト
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
                                children: [
                                  thumbnailPage,
                                  // ブックマーク済みアイコン（右上）
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
                            // ページ番号ラベル（現在ページは赤文字・太字）
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
