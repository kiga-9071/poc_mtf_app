import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/controllers/content_master_controller.dart';
import '../../../shared/components/hooks/locale_controller.dart';
import '../models/entities/pdf_content.dart';
import '../../../shared/features/analytics/services/analytics_service.dart';
import '../widgets/content_preview_card.dart';

enum _BnTab { all, downloaded }

class BacknumberPage extends HookConsumerWidget {
  const BacknumberPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final masterAsync = ref.watch(contentMasterProvider);
    final reloadKey = useState(0);
    final selectedTab = useState(_BnTab.all);

    // バックナンバーページ表示ログ（初回のみ）
    useEffect(() {
      AnalyticsService.logBacknumberPageView();
      return null;
    }, []);

    final lifecycle = useAppLifecycleState();
    useEffect(() {
      if (lifecycle == AppLifecycleState.resumed) {
        ref.read(contentMasterProvider.notifier).refresh();
        reloadKey.value++;
      }
      return null;
    }, [lifecycle]);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF121212) : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('バックナンバー'),
        centerTitle: true,
      ),
      body: masterAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('エラー: $err')),
        data: (master) {
          final contents = master.contentsFor(locale.languageCode);
          final now = master.now;
          final backnumbers = contents
              .where((c) =>
                  c.category != '機内誌' && c.category != 'In-flight Magazine')
              .toList();

          if (backnumbers.isEmpty) {
            return const Center(child: Text('コンテンツがありません'));
          }

          final screenHeight = MediaQuery.of(context).size.height;

          return Column(
            children: [
              // ── 切り替えタブ ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Container(
                  height: 48,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      _TabButton(
                        label: '一覧',
                        selected: selectedTab.value == _BnTab.all,
                        onTap: () {
                          selectedTab.value = _BnTab.all;
                          AnalyticsService.logBacknumberTabSwitch(
                              tabName: 'all');
                        },
                      ),
                      _TabButton(
                        label: 'ダウンロード済み',
                        selected: selectedTab.value == _BnTab.downloaded,
                        onTap: () {
                          selectedTab.value = _BnTab.downloaded;
                          AnalyticsService.logBacknumberTabSwitch(
                              tabName: 'downloaded');
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ── コンテンツグリッド ────────────────────────────────────────
              Expanded(
                child: _BacknumberGrid(
                  key: ValueKey(
                      'bn_${reloadKey.value}_${selectedTab.value.name}'),
                  backnumbers: backnumbers,
                  langCode: locale.languageCode,
                  now: now,
                  tab: selectedTab.value,
                  screenHeight: screenHeight,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── _BacknumberGrid ────────────────────────────────────────────────────────────

class _BacknumberGrid extends HookWidget {
  const _BacknumberGrid({
    super.key,
    required this.backnumbers,
    required this.langCode,
    required this.now,
    required this.tab,
    required this.screenHeight,
  });

  final List<PdfContent> backnumbers;
  final String langCode;
  final DateTime now;
  final _BnTab tab;
  final double screenHeight;

  @override
  Widget build(BuildContext context) {
    final dirFuture = useMemoized(getApplicationDocumentsDirectory);
    final dirSnapshot = useFuture(dirFuture);

    final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      mainAxisExtent: screenHeight < 700 ? 240.0 : 260.0,
    );
    const padding = EdgeInsets.fromLTRB(24, 0, 24, 24);

    if (tab == _BnTab.downloaded) {
      if (!dirSnapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final dir = dirSnapshot.data!;
      final items = backnumbers.where((c) {
        final path = buildSavePath(dir, c, langCode);
        return File(path).existsSync();
      }).toList();

      if (items.isEmpty) {
        return const Center(
          child: Text(
            'ダウンロード済みのコンテンツはありません',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }

      return GridView.builder(
        padding: padding,
        gridDelegate: gridDelegate,
        itemCount: items.length,
        itemBuilder: (context, index) => ContentPreviewCard(
          content: items[index],
          langCode: langCode,
          isAvailable: items[index].isAvailableAt(now),
        ),
      );
    }

    // 一覧タブ
    return GridView.builder(
      padding: padding,
      gridDelegate: gridDelegate,
      itemCount: backnumbers.length,
      itemBuilder: (context, index) => ContentPreviewCard(
        content: backnumbers[index],
        langCode: langCode,
        isAvailable: backnumbers[index].isAvailableAt(now),
      ),
    );
  }
}

// ── _TabButton ────────────────────────────────────────────────────────────────

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFCC0000) : Colors.white,
            borderRadius: BorderRadius.circular(23),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF333333),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
