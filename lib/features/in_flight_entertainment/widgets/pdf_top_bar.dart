import 'package:flutter/material.dart';

import '../../../core/utils/l10n.dart';
import '../constants/pdf_viewer_constants.dart';

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
    required this.ttsStatus,
    required this.onTtsTap,
    this.isSplitMode = false,
    this.onSplitToggle,
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

  /// TTS の現在の状態
  final TtsStatus ttsStatus;

  /// 読み上げボタンのタップコールバック
  final VoidCallback onTtsTap;

  /// 見開き分割モードが有効かどうか
  final bool isSplitMode;

  /// 見開き分割モードのトグルコールバック（null = ボタン非表示）
  final VoidCallback? onSplitToggle;

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
              // ページ数・メモ・ブックマーク・読み上げボタン（PDFロード後のみ表示）
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
                // 読み上げボタン
                IconButton(
                  icon: switch (ttsStatus) {
                    TtsStatus.loading => SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: fgColor,
                        ),
                      ),
                    TtsStatus.speaking => const Icon(Icons.stop_circle_outlined,
                        color: kPdfRedPrimary),
                    TtsStatus.idle => Icon(Icons.volume_up_outlined,
                        color: fgColor),
                  },
                  tooltip: switch (ttsStatus) {
                    TtsStatus.loading => AppL10n.of(context).ttsLoading,
                    TtsStatus.speaking => AppL10n.of(context).ttsStop,
                    TtsStatus.idle => AppL10n.of(context).ttsRead,
                  },
                  onPressed: onTtsTap,
                ),
                // 見開き分割モードトグルボタン
                if (onSplitToggle != null)
                  IconButton(
                    icon: Icon(
                      Icons.vertical_split,
                      color: isSplitMode ? Colors.lightBlue : fgColor,
                    ),
                    tooltip: isSplitMode ? '見開き分割: ON' : '見開き分割: OFF',
                    onPressed: onSplitToggle,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
