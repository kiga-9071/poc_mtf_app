import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../controllers/content_master_controller.dart';
import '../../controllers/locale_controller.dart';
import 'content_preview_card.dart';

class BacknumberPage extends HookConsumerWidget {
  const BacknumberPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final masterAsync = ref.watch(contentMasterProvider);
    final reloadKey = useState(0);

    final lifecycle = useAppLifecycleState();
    useEffect(() {
      if (lifecycle == AppLifecycleState.resumed) {
        ref.read(contentMasterProvider.notifier).refresh();
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

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              mainAxisExtent: 260,
            ),
            itemCount: backnumbers.length,
            itemBuilder: (context, index) => ContentPreviewCard(
              key: ValueKey('bn_${reloadKey.value}_$index'),
              content: backnumbers[index],
              langCode: locale.languageCode,
              isAvailable: backnumbers[index].isAvailableAt(now),
            ),
          );
        },
      ),
    );
  }
}
