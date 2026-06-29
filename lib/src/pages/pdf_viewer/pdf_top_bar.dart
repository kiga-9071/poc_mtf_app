import 'package:flutter/material.dart';

import '../../l10n.dart';

/// PDFビューアー上部のカスタムバー。
/// 標準の AppBar を使わず独自実装することで PDF 上にオーバーレイ表示できる。
class PdfTopBar extends StatelessWidget {
  const PdfTopBar({
    super.key,
    required this.title,
    required this.currentPage,
    required this.pageCount,
    required this.isBookmarked,
    required this.hasMemo,
    required this.onMenuTap,
    required this.onBookmarkTap,
    required this.onMemoTap,
    required this.onBack,
  });

  /// AppBar に表示するタイトル（ファイル名）
  final String title;

  /// 現在のページ番号（"3 / 10" 形式で表示）
  final int currentPage;

  /// 総ページ数（0 = 未ロード）
  final int pageCount;

  /// 現在ページがブックマーク済みかどうか
  final bool isBookmarked;

  /// 現在ページにメモが存在するかどうか
  final bool hasMemo;

  /// サイドドロワーを開くコールバック
  final VoidCallback onMenuTap;

  /// ブックマーク切り替えコールバック（null = ボタン無効）
  final VoidCallback? onBookmarkTap;

  /// メモ編集コールバック（null = ボタン無効）
  final VoidCallback? onMemoTap;

  /// 一覧画面に戻るコールバック
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    // ステータスバーの高さ分だけ上部に余白を設ける
    final topPadding = MediaQuery.of(context).padding.top;
    // ライト: 白背景・黒アイコン／ダーク: 濃いグレー背景・白アイコン
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final fgColor = isDark ? Colors.white : Colors.black;

    return Container(
      color: bgColor.withValues(alpha: 0.97),
      padding: EdgeInsets.only(top: topPadding),
      child: SizedBox(
        height: kToolbarHeight,
        child: IconTheme(
          data: IconThemeData(color: fgColor),
          child: Row(
            children: [
              // 一覧に戻るボタン
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: AppL10n.of(context).backToList,
                onPressed: onBack,
              ),
              // サイドドロワーを開くメニューボタン
              IconButton(
                icon: const Icon(Icons.menu),
                tooltip: AppL10n.of(context).menuLabel,
                onPressed: onMenuTap,
              ),
              // ファイル名（長い場合は省略表示）
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: fgColor),
                ),
              ),
              // ページ数・メモ・ブックマークボタン（PDFロード後のみ表示）
              if (pageCount > 0) ...[
                Text(
                  '$currentPage / $pageCount',
                  style: TextStyle(fontSize: 14, color: fgColor),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    hasMemo ? Icons.edit_note : Icons.edit_note_outlined,
                    color: hasMemo ? Colors.lightBlue : fgColor,
                  ),
                  tooltip: hasMemo
                      ? AppL10n.of(context).editMemo
                      : AppL10n.of(context).addMemo,
                  onPressed: onMemoTap,
                ),
                IconButton(
                  icon: Icon(
                    isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                    color: isBookmarked ? Colors.amber : fgColor,
                  ),
                  tooltip: isBookmarked
                      ? AppL10n.of(context).removeBookmark
                      : AppL10n.of(context).addBookmark,
                  onPressed: onBookmarkTap,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
