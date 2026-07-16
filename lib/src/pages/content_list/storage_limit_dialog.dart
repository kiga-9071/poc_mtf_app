import 'package:flutter/material.dart';

import '../../services/storage_limit_service.dart';

// ── 上限超過警告ダイアログ ────────────────────────────────────────────────────

/// 保存容量が上限に達したときに表示する警告ダイアログ。
/// ダウンロードをブロックし、ユーザーに削除 or 設定変更を促す。
Future<void> showStorageLimitExceededDialog(
  BuildContext context, {
  required int usage,
  required int limit,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
          SizedBox(width: 8),
          Flexible(child: Text('保存容量の上限に達しました')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StorageUsageBar(usage: usage, limit: limit),
          const SizedBox(height: 12),
          const Text(
            '不要なPDFを削除するか、設定で上限を変更してください。',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );
}

// ── ストレージ設定ダイアログ ──────────────────────────────────────────────────

/// ストレージ設定ダイアログ。上限値をラジオボタンで変更できる。
Future<void> showStorageSettingsDialog(BuildContext context) async {
  final limit = await StorageLimitService.getLimit();
  final usage = await StorageLimitService.getTotalUsage();
  if (!context.mounted) return;

  var selectedLimit = limit;

  // 選択肢: (MB値, 表示ラベル)
  const options = [
    (100, '100 MB'),
    (200, '200 MB'),
    (500, '500 MB（デフォルト）'),
    (1024, '1 GB'),
    (2048, '2 GB'),
  ];

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.storage),
            SizedBox(width: 8),
            Text('ストレージ設定'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StorageUsageBar(usage: usage, limit: selectedLimit),
              const SizedBox(height: 16),
              const Text(
                '保存上限',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 4),
              ...options.map(
                (opt) => RadioListTile<int>(
                  title: Text(opt.$2),
                  value: opt.$1 * 1024 * 1024,
                  groupValue: selectedLimit,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) {
                    if (v != null) setState(() => selectedLimit = v);
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              await StorageLimitService.setLimit(selectedLimit);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

// ── 共通ウィジェット ───────────────────────────────────────────────────────────

/// 使用量 / 上限 をテキストとプログレスバーで表示するウィジェット。
class _StorageUsageBar extends StatelessWidget {
  const _StorageUsageBar({required this.usage, required this.limit});

  final int usage;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final ratio = limit > 0 ? (usage / limit).clamp(0.0, 1.0) : 0.0;
    final isOver = ratio >= 1.0;
    final barColor = isOver
        ? Colors.red
        : ratio >= 0.8
            ? Colors.orange
            : Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '使用量: ${StorageLimitService.formatBytes(usage)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isOver ? Colors.red : null,
              ),
            ),
            Text(
              '/ ${StorageLimitService.formatBytes(limit)}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
        ),
      ],
    );
  }
}
