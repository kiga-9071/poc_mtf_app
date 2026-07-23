import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences に保存するキー名
const _kThemeModeKey = 'theme_mode';

/// アプリ全体のテーマモード（ライト／ダーク／システム）を管理するプロバイダー。
/// 選択したモードは端末ストレージに永続化され、次回起動時にも復元される。
final themeModeProvider =
    StateNotifierProvider<ThemeController, ThemeMode>((ref) => ThemeController());

/// テーマモードの状態を保持・変更するコントローラー。
/// 初期値は ThemeMode.system（端末のダークモード設定に自動追従）。
class ThemeController extends StateNotifier<ThemeMode> {
  /// デフォルトを system に設定し、保存済み設定を非同期で読み込む
  ThemeController() : super(ThemeMode.system) {
    _load();
  }

  /// SharedPreferences から保存済みのテーマモードを読み込む。
  /// 保存値がない場合はデフォルトの ThemeMode.system のままにする。
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // 保存されている文字列（"system" / "light" / "dark"）を取得
    final name = prefs.getString(_kThemeModeKey);
    if (name == null) return;
    // 文字列を ThemeMode 列挙値に変換（一致しなければ system にフォールバック）
    state = ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  /// テーマモードを変更し、SharedPreferences に永続化する。
  Future<void> set(ThemeMode mode) async {
    state = mode; // 状態を即時更新（UIに反映）
    final prefs = await SharedPreferences.getInstance();
    // ThemeMode.name は "system" / "light" / "dark" の文字列
    await prefs.setString(_kThemeModeKey, mode.name);
  }
}
