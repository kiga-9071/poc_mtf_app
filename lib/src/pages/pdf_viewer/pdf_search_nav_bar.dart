import 'package:flutter/material.dart';

import '../../l10n.dart';

/// キーワード検索のヒット一覧をナビゲートするバー。
/// トップバーの直下に表示され、検索クエリ・件数・前後移動ボタンを持つ。
class PdfSearchNavBar extends StatelessWidget {
  const PdfSearchNavBar({
    super.key,
    required this.query,
    required this.totalCount,
    required this.currentIndex,
    required this.currentPage,
    required this.onClose,
    required this.onPrev,
    required this.onNext,
  });

  /// 検索キーワード文字列（バーに「"keyword"」形式で表示）
  final String query;

  /// 全ヒット件数
  final int totalCount;

  /// 現在フォーカスされているヒットのインデックス（0始まり）
  final int currentIndex;

  /// 現在フォーカスされているヒットが存在するページ番号
  final int currentPage;

  /// 検索を終了してバーを閉じるコールバック
  final VoidCallback onClose;

  /// 前のヒットに移動するコールバック
  final VoidCallback onPrev;

  /// 次のヒットに移動するコールバック
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    // ヒットが複数件ある場合のみ前後ボタンを有効化
    final hasMultiple = totalCount > 1;

    return Container(
      color: const Color(0xFF1565C0).withValues(alpha: 0.93), // 青背景
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          // 検索を閉じるボタン
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            tooltip: AppL10n.of(context).closeSearch,
            onPressed: onClose,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          // 検索キーワードの表示（長い場合は省略）
          Expanded(
            child: Text(
              '「$query」',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 現在フォーカスヒットが存在するページ番号
          Text(
            '$currentPage ${AppL10n.of(context).page}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 4),
          // 前のヒットへ移動するボタン
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            tooltip: AppL10n.of(context).prevResult,
            onPressed: hasMultiple ? onPrev : null,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          // "現在番号 / 全件数" の表示（例: "3 / 10"）
          Text(
            '${currentIndex + 1} / $totalCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          // 次のヒットへ移動するボタン
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            tooltip: AppL10n.of(context).nextResult,
            onPressed: hasMultiple ? onNext : null,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}
