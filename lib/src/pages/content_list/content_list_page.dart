import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/content_master_controller.dart';
import '../../controllers/locale_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../l10n.dart';
import 'content_list_card.dart';
import 'content_preview_card.dart';

// ── 表示モード ────────────────────────────────────────────────────────────────

/// コンテンツ一覧の表示モード。
/// - list   : テキスト情報を中心とした縦スクロールリスト
/// - preview: PDFの1ページ目サムネイルを前面に出した2列グリッド
enum _ViewMode { list, preview }

// ── ストレージ初期化（テスト用） ────────────────────────────────────────────

/// ダウンロード済みPDFとSharedPreferencesのデータをすべて削除する。
/// テスト目的のみ。確認ダイアログを表示してから実行する。
Future<void> resetStorage(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ストレージを初期化'),
      content: const Text(
        'ダウンロード済みPDFファイルとブックマークなど、すべてのデータを削除します。\nこの操作は取り消せません。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('キャンセル'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('初期化'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final dir = await getApplicationDocumentsDirectory();
  for (final entity in dir.listSync()) {
    if (entity is File && entity.path.endsWith('.pdf')) {
      await entity.delete();
    }
  }

  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();

  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('ストレージを初期化しました')));
  }
}

// ── テーマ切替ダイアログ ────────────────────────────────────────────────────

/// テーマモード（システム設定 / ライト / ダーク）を選択するダイアログを表示する。
Future<void> showThemeModeDialog(BuildContext context, WidgetRef ref) {
  final l10n = AppL10n.of(context);
  final current = ref.read(themeModeProvider);

  final options = [
    (ThemeMode.system, Icons.brightness_auto, l10n.themeSystem),
    (ThemeMode.light, Icons.light_mode, l10n.themeLight),
    (ThemeMode.dark, Icons.dark_mode, l10n.themeDark),
  ];

  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.brightness_6, size: 20),
          const SizedBox(width: 8),
          Text(l10n.themeLabel),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: options.map((entry) {
          final (mode, icon, label) = entry;
          final isSelected = mode == current;
          return ListTile(
            leading: Icon(icon),
            title: Text(label),
            trailing: isSelected
                ? Icon(
                    Icons.check_circle,
                    color: Theme.of(ctx).colorScheme.primary,
                  )
                : null,
            selected: isSelected,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onTap: () {
              ref.read(themeModeProvider.notifier).set(mode);
              Navigator.of(ctx).pop();
            },
          );
        }).toList(),
      ),
    ),
  );
}

// ── 言語切替ダイアログ ──────────────────────────────────────────────────────

/// 表示言語（日本語 / 英語）を選択するダイアログを表示する。
Future<void> showLanguageDialog(BuildContext context, WidgetRef ref) {
  final l10n = AppL10n.of(context);
  final current = ref.read(localeProvider);

  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.language, size: 20),
          const SizedBox(width: 8),
          Text(l10n.language),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: supportedLocales.map((locale) {
          final isSelected = locale.languageCode == current.languageCode;
          final label = locale.languageCode == 'ja'
              ? l10n.languageJa
              : l10n.languageEn;
          final flag = locale.languageCode == 'ja' ? '🇯🇵' : '🇺🇸';
          return ListTile(
            leading: Text(flag, style: const TextStyle(fontSize: 24)),
            title: Text(label),
            trailing: isSelected
                ? Icon(
                    Icons.check_circle,
                    color: Theme.of(ctx).colorScheme.primary,
                  )
                : null,
            selected: isSelected,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onTap: () {
              ref.read(localeProvider.notifier).setLocale(locale);
              Navigator.of(ctx).pop();
            },
          );
        }).toList(),
      ),
    ),
  );
}

// ── ContentListPage ─────────────────────────────────────────────────────────

/// PDFコンテンツの一覧を表示するホーム画面。
/// AppBar の切替ボタンで「リスト表示」と「プレビュー表示」を切り替えられる。
class ContentListPage extends HookConsumerWidget {
  const ContentListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final l10n = AppL10n.of(context);

    // サーバーから取得したコンテンツマスター（表示期間・信頼できる時刻を含む）
    final masterAsync = ref.watch(contentMasterProvider);

    // ストレージ初期化後にカード状態を強制リセットするためのキー
    final reloadKey = useState(0);

    // 表示モード（デフォルトはグリッド表示）
    final viewMode = useState(_ViewMode.preview);

    // アプリ復帰時に最新マスターデータを再取得する
    final lifecycle = useAppLifecycleState();
    useEffect(() {
      if (lifecycle == AppLifecycleState.resumed) {
        ref.read(contentMasterProvider.notifier).refresh();
      }
      return null;
    }, [lifecycle]);

    // テーマモードアイコン（現在のモードを反映）
    final themeIcon = switch (themeMode) {
      ThemeMode.dark => Icons.dark_mode,
      ThemeMode.light => Icons.light_mode,
      _ => Icons.brightness_auto,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.contentList),
        actions: [
          // 表示モード切替ボタン
          IconButton(
            icon: Icon(
              viewMode.value == _ViewMode.list
                  ? Icons.grid_view
                  : Icons.view_list,
            ),
            tooltip: viewMode.value == _ViewMode.list
                ? l10n.switchToPreview
                : l10n.switchToList,
            onPressed: () {
              viewMode.value = viewMode.value == _ViewMode.list
                  ? _ViewMode.preview
                  : _ViewMode.list;
            },
          ),
          // テーマ切替ボタン
          IconButton(
            icon: Icon(themeIcon),
            tooltip: l10n.themeLabel,
            onPressed: () => showThemeModeDialog(context, ref),
          ),
          // 言語切替ボタン
          IconButton(
            icon: const Icon(Icons.language),
            tooltip: l10n.language,
            onPressed: () => showLanguageDialog(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: masterAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text(l10n.loadError('$err'))),
              data: (master) {
                final contents = master.contentsFor(locale.languageCode);
                final now = master.now;
                return viewMode.value == _ViewMode.preview
                    // プレビューモード: 3列グリッドでPDFサムネイルを表示
                    ? GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          mainAxisExtent: 260,
                        ),
                        itemCount: contents.length,
                        itemBuilder: (context, index) => ContentPreviewCard(
                          key: ValueKey('${reloadKey.value}_$index'),
                          content: contents[index],
                          langCode: locale.languageCode,
                          isAvailable: contents[index].isAvailableAt(now),
                        ),
                      )
                    // リストモード: テキスト情報を中心とした縦スクロールリスト
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: contents.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => ContentListCard(
                          key: ValueKey('${reloadKey.value}_$index'),
                          content: contents[index],
                          langCode: locale.languageCode,
                          isAvailable: contents[index].isAvailableAt(now),
                        ),
                      );
              },
            ),
          ),
          // ── テスト用: ストレージ初期化ボタン ───────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              label: const Text(
                'ストレージを初期化 (テスト用)',
                style: TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
              ),
              onPressed: () async {
                await resetStorage(context);
                if (context.mounted) {
                  reloadKey.value++;
                  ref.read(contentMasterProvider.notifier).refresh();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
