import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/content_master_controller.dart';
import '../../controllers/locale_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../l10n.dart';
import 'content_featured_card.dart';
import 'content_preview_card.dart';
import 'shop_tab.dart';
import 'youtube_tab.dart';

// ── ストレージ初期化（テスト用） ────────────────────────────────────────────

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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('ストレージを初期化しました')));
  }
}

// ── テーマ切替ダイアログ ────────────────────────────────────────────────────

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
                ? Icon(Icons.check_circle,
                    color: Theme.of(ctx).colorScheme.primary)
                : null,
            selected: isSelected,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                ? Icon(Icons.check_circle,
                    color: Theme.of(ctx).colorScheme.primary)
                : null,
            selected: isSelected,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

class ContentListPage extends HookConsumerWidget {
  const ContentListPage({super.key});

  static Widget _buildFilterRow(
    List<(String, double)> items,
    ValueNotifier<String?> selectedTag,
    Color primary,
  ) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: items.asMap().entries.map((entry) {
          final (tag, width) = entry.value;
          final isLast = entry.key == items.length - 1;
          final isSelected = selectedTag.value == tag;
          return Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 8),
            child: GestureDetector(
              onTap: () => selectedTag.value = isSelected ? null : tag,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: width,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected ? primary : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isSelected ? primary : const Color(0xFFB7C1CD),
                  ),
                ),
                child: Center(
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color:
                          isSelected ? Colors.white : const Color(0xFF2A344B),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static Widget _buildStaticArticleCard({
    required BuildContext context,
    required String imagePath,
    required String tag,
    required String title,
    String? url,
  }) {
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A2A344B),
            blurRadius: 10,
            spreadRadius: -2,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 163,
              child: Image.asset(imagePath, fit: BoxFit.cover, width: double.infinity),
            ),
            Expanded(
              child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE1E3E6),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w300,
                          color: Colors.black),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Colors.black),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ),
          ],
        ),
      ),
    );
    if (url == null) return card;
    return GestureDetector(
      onTap: () => context.push('/webview', extra: url),
      child: card,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final l10n = AppL10n.of(context);
    final masterAsync = ref.watch(contentMasterProvider);
    final reloadKey = useState(0);
    final selectedTag = useState<String?>('旅・文化');
    final scrollController = useScrollController();

    final lifecycle = useAppLifecycleState();
    useEffect(() {
      if (lifecycle == AppLifecycleState.resumed) {
        ref.read(contentMasterProvider.notifier).refresh();
      }
      return null;
    }, [lifecycle]);

    final themeIcon = switch (themeMode) {
      ThemeMode.dark => Icons.dark_mode,
      ThemeMode.light => Icons.light_mode,
      _ => Icons.brightness_auto,
    };

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.contentList),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'SKYWARD'),
              Tab(text: 'JAL SHOP'),
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Youtube【公式】'),
                ),
              ),
            ],
            indicatorColor: Color(0xFFCC0000),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorWeight: 3,
            labelColor: Color(0xFFCC0000),
            unselectedLabelColor: Colors.grey,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
          ),
          actions: [
            IconButton(
              icon: Icon(themeIcon),
              tooltip: l10n.themeLabel,
              onPressed: () => showThemeModeDialog(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.language),
              tooltip: l10n.language,
              onPressed: () => showLanguageDialog(context, ref),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'reset') {
                  await resetStorage(context);
                  if (context.mounted) {
                    reloadKey.value++;
                    ref.read(contentMasterProvider.notifier).refresh();
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'reset',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('ストレージを初期化',
                          style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: TabBarView(
          children: [
            // ── SKYWARDタブ ────────────────────────────────────────────────
            masterAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text(l10n.loadError('$err'))),
              data: (master) {
                final contents =
                    master.contentsFor(locale.languageCode);
                final now = master.now;

                final featured = contents
                    .where((c) =>
                        c.category == '機内誌' ||
                        c.category == 'In-flight Magazine')
                    .firstOrNull;
                final others = contents
                    .where((c) =>
                        c.category != '機内誌' &&
                        c.category != 'In-flight Magazine')
                    .toList();

                const categories = [
                  ('旅・文化', 108.0),
                  ('グルメ・お土産', 152.0),
                  ('物語', 78.0),
                  ('エンタメ', 108.0),
                  ('JAL Stories', 141.0),
                ];

                final filtered = others
                    .where((c) => c.category == selectedTag.value)
                    .toList();

                final isDark =
                    Theme.of(context).brightness == Brightness.dark;
                final bgColor = isDark
                    ? const Color(0xFF121212)
                    : const Color(0xFFF2F2F7);
                final cardColor =
                    isDark ? const Color(0xFF1C1C1E) : Colors.white;
                final primary = Theme.of(context).colorScheme.primary;

                return ColoredBox(
                  color: bgColor,
                  child: Stack(
                    children: [
                      // 背景画像（タブ直下から高さ344px）
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Image.asset(
                          'assets/diagonal_mask.png',
                          width: 390,
                          height: 344,
                          fit: BoxFit.cover,
                        ),
                      ),
                      ListView(
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      // ── フィーチャー白カード（ヘッダーを内包） ────────
                      if (featured != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                          child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x1A2A344B),
                                    blurRadius: 10,
                                    spreadRadius: -2,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Card(
                                color: cardColor,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                clipBehavior: Clip.antiAlias,
                                child: ContentFeaturedCard(
                                  key: ValueKey(
                                      'featured_${reloadKey.value}'),
                                  content: featured,
                                  langCode: locale.languageCode,
                                  isAvailable: featured.isAvailableAt(now),
                                  inline: true,
                                ),
                              ),
                            ),
                        ),

                      const SizedBox(height: 32),

                      // ── Pick UP セクション ────────────────────────────
                      const Padding(
                        padding: EdgeInsets.only(left: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pick UP',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '人気記事をピックアップ',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w300,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── カテゴリフィルタータグ（2行独立ボタン） ────────
                      Column(
                        children: [
                          _buildFilterRow(
                            categories.sublist(0, 2),
                            selectedTag,
                            primary,
                          ),
                          const SizedBox(height: 8),
                          _buildFilterRow(
                            categories.sublist(2),
                            selectedTag,
                            primary,
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // ── コンテンツ2列グリッド ─────────────────────────
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 24),
                        child: selectedTag.value == '旅・文化'
                            ? GridView.count(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisCount: 2,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 24,
                                childAspectRatio: 163 / 258,
                                children: [
                                  _buildStaticArticleCard(
                                    context: context,
                                    imagePath: 'assets/kochi_katsuo.jpg',
                                    tag: '高知',
                                    title: '初夏、かつおを食べに',
                                    url: 'https://skywardplus.jal.co.jp/plus_one/other/sightseeing_toyama/',
                                  ),
                                  _buildStaticArticleCard(
                                    context: context,
                                    imagePath: 'assets/local_chain_ramen.jpg',
                                    tag: 'グルメ',
                                    title: '噂のローカルチェーン飯',
                                    url: 'https://skywardplus.jal.co.jp/plus_one/other/sightseeing_kumamoto/',
                                  ),
                                  _buildStaticArticleCard(
                                    context: context,
                                    imagePath: 'assets/sora_gourmet_aomori.jpg',
                                    tag: '青森',
                                    title: '食べたい！買いたい！空グルメ！',
                                    url: 'https://skywardplus.jal.co.jp/gourmet/crew/soysoy_cafe/',
                                  ),
                                  _buildStaticArticleCard(
                                    context: context,
                                    imagePath: 'assets/ichiro_malt.jpg',
                                    tag: '秩父',
                                    title: 'イッピンに宿る物語',
                                    url: 'https://skywardplus.jal.co.jp/view/crew/nihondaira_yume_terrace/',
                                  ),
                                  _buildStaticArticleCard(
                                    context: context,
                                    imagePath: 'assets/pickup_carlease.jpg',
                                    tag: 'カーリース',
                                    title: '【2026年6月最新】カーリースおすすめ12社を比較して紹介！',
                                    url: 'https://skywardplus.jal.co.jp/plus_one/solution/car_lease/recommend/',
                                  ),
                                  _buildStaticArticleCard(
                                    context: context,
                                    imagePath: 'assets/pickup_okamoto_sanbashi.jpg',
                                    tag: '千葉',
                                    title: '岡本桟橋（原岡桟橋）徹底ガイド｜絶景の夕日と富士山、アクセス情報まとめ',
                                    url: 'https://skywardplus.jal.co.jp/hanto/plus_one/okamoto-sanbashi/',
                                  ),
                                ],
                              )
                            : selectedTag.value == null
                                ? const SizedBox.shrink()
                                : GridView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                      mainAxisExtent: MediaQuery.of(context).size.height < 700 ? 240.0 : 260.0,
                                    ),
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) =>
                                        ContentPreviewCard(
                                      key: ValueKey(
                                          '${reloadKey.value}_$index'),
                                      content: filtered[index],
                                      langCode: locale.languageCode,
                                      isAvailable:
                                          filtered[index].isAvailableAt(now),
                                    ),
                                  ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                    ],
                  ),
                );
              },
            ),

            // ── JAL SHOPタブ ──────────────────────────────────────────────
            const ShopTab(),

            // ── Youtubeタブ ───────────────────────────────────────────────
            const YoutubeTab(),
          ],
        ),
      ),
    );
  }
}
