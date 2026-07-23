import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// ズーム倍率が [_kThreshold] を超えたとき右上に表示するナビゲーション小窓。
///
/// [PdfDocumentViewBuilder.file] を使って pdfrx のドキュメント管理下で
/// [PdfPageView] を動かすことで確実にサムネイルを表示する。
/// 同じファイルパスなら pdfrx の内部キャッシュによりドキュメントは再読み込みされない。
class PdfMiniMap extends StatefulWidget {
  const PdfMiniMap({
    super.key,
    required this.filePath,
    required this.pageNumber,
    required this.transformController,
    required this.viewportSize,
    this.width = 70.0,
  });

  final String filePath;
  final int pageNumber;
  final TransformationController transformController;
  final Size viewportSize;
  final double width;

  @override
  State<PdfMiniMap> createState() => _PdfMiniMapState();
}

class _PdfMiniMapState extends State<PdfMiniMap> {
  static const _kThreshold = 2.0;

  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.transformController.addListener(_onTransform);
  }

  @override
  void dispose() {
    widget.transformController.removeListener(_onTransform);
    super.dispose();
  }

  @override
  void didUpdateWidget(PdfMiniMap old) {
    super.didUpdateWidget(old);
    if (old.transformController != widget.transformController) {
      old.transformController.removeListener(_onTransform);
      widget.transformController.addListener(_onTransform);
    }
  }

  void _onTransform() {
    if (!mounted) return;
    final nowVisible =
        widget.transformController.value.getMaxScaleOnAxis() > _kThreshold;
    if (nowVisible != _visible) {
      setState(() => _visible = nowVisible);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 6,
            offset: Offset(1, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        // PdfDocumentViewBuilder.file で pdfrx ドキュメント管理下に入る。
        // 同一ファイルパスのドキュメントはキャッシュで共有されるため二重読み込みなし。
        child: PdfDocumentViewBuilder.file(
          widget.filePath,
          builder: (context, doc) {
            if (doc == null ||
                widget.pageNumber < 1 ||
                widget.pageNumber > doc.pages.length) {
              return SizedBox(width: widget.width, height: widget.width);
            }

            final page = doc.pages[widget.pageNumber - 1];
            final pageAspect = page.width / page.height;
            final miniHeight = widget.width / pageAspect;

            return SizedBox(
              width: widget.width,
              height: miniHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // PDF ページをサムネイル表示（pdfrx 管理下なので確実にレンダリングされる）
                  PdfPageView(
                    document: doc,
                    pageNumber: widget.pageNumber,
                    maximumDpi: 150,
                    // デフォルトのドロップシャドウを無効化（外側の DecoratedBox が担う）
                    decoration: const BoxDecoration(color: Colors.white),
                  ),
                  // 現在の表示領域を赤枠でオーバーレイ
                  CustomPaint(
                    painter: _MiniMapPainter(
                      transformController: widget.transformController,
                      viewportSize: widget.viewportSize,
                      pageAspect: pageAspect,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 現在の表示領域（赤枠）を描画する CustomPainter。
///
/// [repaint] に transformController を渡すことで、pan/zoom のたびに
/// ウィジェット再ビルドなしで赤枠を再描画できる。
class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter({
    required this.transformController,
    required this.viewportSize,
    required this.pageAspect,
  }) : super(repaint: transformController);

  final TransformationController transformController;
  final Size viewportSize;
  final double pageAspect;

  @override
  void paint(Canvas canvas, Size size) {
    final matrix = transformController.value;
    Matrix4 inv;
    try {
      inv = Matrix4.inverted(matrix);
    } catch (_) {
      return;
    }

    final tl = MatrixUtils.transformPoint(inv, Offset.zero);
    final br = MatrixUtils.transformPoint(
      inv,
      Offset(viewportSize.width, viewportSize.height),
    );
    final visibleInChild = Rect.fromPoints(tl, br);

    // PdfPageView の Align+AspectRatio レイアウトと同じ計算でページ矩形を求める
    final pageRect = _pageRectInViewport(viewportSize, pageAspect);
    final sx = size.width / pageRect.width;
    final sy = size.height / pageRect.height;

    final redBox = Rect.fromLTRB(
      ((visibleInChild.left - pageRect.left) * sx).clamp(0.0, size.width),
      ((visibleInChild.top - pageRect.top) * sy).clamp(0.0, size.height),
      ((visibleInChild.right - pageRect.left) * sx).clamp(0.0, size.width),
      ((visibleInChild.bottom - pageRect.top) * sy).clamp(0.0, size.height),
    );

    // 半透明赤塗り
    canvas.drawRect(
      redBox,
      Paint()
        ..color = Colors.red.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    // 赤枠
    canvas.drawRect(
      redBox,
      Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // 小窓の内側ボーダー
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Colors.white38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// viewport 内でのページ実描画矩形を返す。
  /// PdfPageView._defaultDecorationBuilder の Align(center)+AspectRatio と同じ計算。
  static Rect _pageRectInViewport(Size viewport, double pageAspect) {
    final viewAspect = viewport.width / viewport.height;
    if (viewAspect > pageAspect) {
      final w = viewport.height * pageAspect;
      return Rect.fromLTWH((viewport.width - w) / 2, 0, w, viewport.height);
    } else {
      final h = viewport.width / pageAspect;
      return Rect.fromLTWH(0, (viewport.height - h) / 2, viewport.width, h);
    }
  }

  @override
  bool shouldRepaint(_MiniMapPainter old) =>
      old.transformController != transformController ||
      old.viewportSize != viewportSize ||
      old.pageAspect != pageAspect;
}
