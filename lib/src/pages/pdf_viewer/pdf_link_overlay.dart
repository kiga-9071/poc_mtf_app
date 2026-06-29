import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDFページのリンク領域を透明ボタンとして覆うオーバーレイウィジェット。
/// - 外部URLリンク → onUrlLink コールバックで通知（インアプリWebViewで開く）
/// - 内部ページリンク（目次など） → onDestLink コールバックで通知（ページジャンプ）
class PdfLinkOverlay extends StatefulWidget {
  const PdfLinkOverlay({
    super.key,
    required this.page,
    required this.pageSize,
    required this.onUrlLink,
    required this.onDestLink,
  });

  /// リンクを読み込む対象のPDFページ
  final PdfPage page;

  /// ページの表示サイズ（リンク矩形の座標変換に使用）
  final Size pageSize;

  /// 外部URLリンクタップ時のコールバック
  final void Function(Uri url) onUrlLink;

  /// 内部ページリンクタップ時のコールバック
  final void Function(PdfDest dest) onDestLink;

  @override
  State<PdfLinkOverlay> createState() => _PdfLinkOverlayState();
}

class _PdfLinkOverlayState extends State<PdfLinkOverlay> {
  /// このページのリンク一覧（null = 未ロード）
  List<PdfLink>? _links;

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  @override
  void didUpdateWidget(PdfLinkOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ページが変わったときにリンク情報を再取得する
    if (oldWidget.page != widget.page) _loadLinks();
  }

  /// ページのリンク情報を非同期で読み込む。
  Future<void> _loadLinks() async {
    final links = await widget.page.loadLinks();
    if (mounted) setState(() => _links = links);
  }

  @override
  Widget build(BuildContext context) {
    if (_links == null || _links!.isEmpty) return const SizedBox.shrink();

    // 各リンクの全矩形領域を GestureDetector で覆う
    return Stack(
      children: _links!
          .expand((link) => link.rects.map((rect) {
                // PDF座標系から画面座標系に変換
                final r = rect.toRect(
                  page: widget.page,
                  scaledPageSize: widget.pageSize,
                );
                return Positioned(
                  left: r.left,
                  top: r.top,
                  width: r.width,
                  height: r.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (link.url != null) {
                        widget.onUrlLink(link.url!); // 外部URLリンク
                      } else if (link.dest != null) {
                        widget.onDestLink(link.dest!); // 内部ページリンク
                      }
                    },
                    // リンク領域を薄い青で色づけして視覚的にリンクと分かるようにする
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                );
              }))
          .toList(),
    );
  }
}
