import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PDF の取得元を表す列挙値。
enum SourceMode { server, local }

const _kSourceModeKey = 'source_mode';

/// PDF 取得元モード（サーバー／内蔵）を管理するプロバイダー。
/// 選択したモードは端末ストレージに永続化され、次回起動時にも復元される。
final sourceModeProvider =
    StateNotifierProvider<SourceModeController, SourceMode>(
  (ref) => SourceModeController(),
);

class SourceModeController extends StateNotifier<SourceMode> {
  SourceModeController() : super(SourceMode.server) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kSourceModeKey);
    if (name == null) return;
    state = SourceMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => SourceMode.server,
    );
  }

  Future<void> set(SourceMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSourceModeKey, mode.name);
  }
}
