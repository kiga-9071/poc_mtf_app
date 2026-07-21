import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// TTS 読み上げ中の現在位置を水色でハイライト表示するオーバーレイ。
/// setProgressHandler から得た文字インデックス範囲を PDF 座標に変換して描画する。
class PdfTtsHighlightOverlay extends StatefulWidget {
  const PdfTtsHighlightOverlay({
    super.key,
    required this.page,
    required this.pageSize,
    required this.pageText,
    required this.charStart,
    required this.charEnd,
  });

  final PdfPage page;
  final Size pageSize;

  /// 事前ロード済みのページテキスト（loadText() のキャッシュを渡す）
  final PdfPageText pageText;

  /// ハイライト開始文字インデックス
  final int charStart;

  /// ハイライト終了文字インデックス
  final int charEnd;

  @override
  State<PdfTtsHighlightOverlay> createState() => _PdfTtsHighlightOverlayState();
}

class _PdfTtsHighlightOverlayState extends State<PdfTtsHighlightOverlay> {
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    _computeRect();
  }

  @override
  void didUpdateWidget(PdfTtsHighlightOverlay old) {
    super.didUpdateWidget(old);
    if (old.charStart != widget.charStart ||
        old.charEnd != widget.charEnd ||
        old.pageSize != widget.pageSize) {
      _computeRect();
    }
  }

  void _computeRect() {
    try {
      final range = PdfTextRangeWithFragments.fromTextRange(
        widget.pageText,
        widget.charStart,
        widget.charEnd,
      );
      if (range == null) {
        if (mounted) setState(() => _rect = null);
        return;
      }
      final rect = range.bounds.toRect(
        page: widget.page,
        scaledPageSize: widget.pageSize,
      );
      if (mounted) setState(() => _rect = rect);
    } catch (_) {
      if (mounted) setState(() => _rect = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _rect;
    if (r == null) return const SizedBox.shrink();
    return Stack(
      children: [
        Positioned(
          left: r.left,
          top: r.top,
          width: r.width,
          height: r.height,
          child: Container(
            color: Colors.yellow.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
