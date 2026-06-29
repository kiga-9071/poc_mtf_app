import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences に言語コードを保存するキー名
const _kLocaleKey = 'app_locale';

/// アプリがサポートする言語の一覧。
/// 日本語（ja）と英語（en）の 2 言語対応。
const supportedLocales = [Locale('ja'), Locale('en')];

/// アプリ全体の表示言語を管理するプロバイダー。
/// 選択した言語は端末ストレージに永続化され、次回起動時にも復元される。
final localeProvider =
    StateNotifierProvider<LocaleController, Locale>((ref) => LocaleController());

/// 表示言語の状態を保持・変更するコントローラー。
/// 初期値は日本語（ja）とし、起動時に保存済み設定またはシステム言語を反映する。
class LocaleController extends StateNotifier<Locale> {
  /// デフォルトを日本語に設定し、非同期で保存済み設定を読み込む
  LocaleController() : super(const Locale('ja')) {
    _init();
  }

  /// 起動時の言語初期化処理。
  /// 優先順位: ① 保存済み設定 → ② 端末システム言語 → ③ 日本語（フォールバック）
  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    // ① 保存済みの言語コードを確認
    final saved = prefs.getString(_kLocaleKey);
    if (saved != null && supportedLocales.any((l) => l.languageCode == saved)) {
      state = Locale(saved);
      return;
    }
    // ② 端末のシステム言語を取得し、サポート対象かチェック
    final sys = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    // ③ 未対応言語の場合は日本語にフォールバック
    state = supportedLocales.any((l) => l.languageCode == sys)
        ? Locale(sys)
        : const Locale('ja');
  }

  /// 表示言語を変更し、SharedPreferences に永続化する。
  Future<void> setLocale(Locale locale) async {
    state = locale; // 状態を即時更新（UIに反映）
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, locale.languageCode);
  }
}
