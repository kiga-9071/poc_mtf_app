import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../entities/search_match.dart';

/// 検索ヒット箇所をページ上にハイライト表示するオーバーレイウィジェット。
///
/// - 全ヒット     : 薄い黄色（不透明度 0.30）で塗りつぶし
/// - フォーカス中 : 濃い黄色（不透明度 0.75）で上書き塗りつぶし
///
/// 文字インデックス（charStart/charEnd）から PdfTextRangeWithFragments を生成し、
/// PDF座標系の矩形を画面座標に変換してハイライト位置を決定する。
class PdfSearchHighlightOverlay extends StatefulWidget {
  const PdfSearchHighlightOverlay({
    super.key,
    required this.page,
    required this.pageSize,
    required this.query,
    required this.activeMatch,
  });

  /// ハイライトを表示するPDFページ
  final PdfPage page;

  /// ページの表示サイズ（座標変換に使用）
  final Size pageSize;

  /// 検索キーワード文字列
  final String query;

  /// フォーカス中のヒット（null = このページにフォーカスなし）
  final SearchMatch? activeMatch;

  @override
  State<PdfSearchHighlightOverlay> createState() =>
      _PdfSearchHighlightOverlayState();
}

class _PdfSearchHighlightOverlayState
    extends State<PdfSearchHighlightOverlay> {
  /// このページ上の全ヒット矩形リスト（薄い黄色でハイライト）
  List<Rect> _allRects = [];

  /// フォーカス中のヒット矩形（濃い黄色でハイライト）
  Rect? _activeRect;

  @override
  void initState() {
    super.initState();
    _loadHighlights();
  }

  @override
  void didUpdateWidget(PdfSearchHighlightOverlay old) {
    super.didUpdateWidget(old);
    // ページ・クエリ・サイズ・フォーカス位置が変わったときに再計算
    if (old.page != widget.page ||
        old.query != widget.query ||
        old.pageSize != widget.pageSize ||
        old.activeMatch?.charStart != widget.activeMatch?.charStart) {
      _loadHighlights();
    }
  }

  /// ページのテキストを読み込み、全ヒットのハイライト矩形を計算する。
  /// PdfTextRangeWithFragments.fromTextRange() で文字範囲をPDF座標に変換する。
  Future<void> _loadHighlights() async {
    if (widget.query.isEmpty) {
      if (mounted) setState(() { _allRects = []; _activeRect = null; });
      return;
    }

    final allRects = <Rect>[];
    Rect? activeRect;
    final pattern = RegExp(RegExp.escape(widget.query), caseSensitive: false);

    try {
      final pageText = await widget.page.loadText();
      for (final m in pattern.allMatches(pageText.fullText)) {
        try {
          // 文字インデックス範囲からPDF座標系の矩形を取得
          final range = PdfTextRangeWithFragments.fromTextRange(
              pageText, m.start, m.end);
          if (range == null) continue;
          // PDF座標系 → 画面座標系に変換
          final r = range.bounds.toRect(
            page: widget.page,
            scaledPageSize: widget.pageSize,
          );
          allRects.add(r);
          // フォーカス中のヒットかどうか判定
          if (m.start == widget.activeMatch?.charStart &&
              m.end == widget.activeMatch?.charEnd) {
            activeRect = r;
          }
        } catch (_) {
          // フラグメント変換に失敗した場合はスキップ
        }
      }
    } catch (_) {
      // テキスト読み込みに失敗した場合はハイライトなし
    }

    if (mounted) setState(() { _allRects = allRects; _activeRect = activeRect; });
  }

  @override
  Widget build(BuildContext context) {
    if (_allRects.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: [
        // 全ヒット: 薄い黄色で塗りつぶし
        ..._allRects.map((r) => Positioned(
              left: r.left,
              top: r.top,
              width: r.width,
              height: r.height,
              child: Container(color: Colors.yellow.withValues(alpha: 0.30)),
            )),
        // フォーカス中のヒット: 濃い黄色で上書き（全ヒットより上のレイヤー）
        if (_activeRect != null)
          Positioned(
            left: _activeRect!.left,
            top: _activeRect!.top,
            width: _activeRect!.width,
            height: _activeRect!.height,
            child: Container(color: Colors.yellow.withValues(alpha: 0.75)),
          ),
      ],
    );
  }
}
