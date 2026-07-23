import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// ファイルパスに対応するブックマーク保存キーを生成する。
/// ファイルパスをハッシュ化してキーの重複を防ぐ。
String bookmarkKey(String filePath) => 'bm_${filePath.hashCode}';

/// SharedPreferences からブックマーク済みページ番号のセットを読み込む。
/// 保存されていない場合は空のセットを返す。
Future<Set<int>> loadBookmarks(String filePath) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(bookmarkKey(filePath));
  if (raw == null) return {};
  // JSON配列 "[1, 3, 5]" → Set<int> {1, 3, 5} に変換
  return (jsonDecode(raw) as List<dynamic>).cast<int>().toSet();
}

/// ブックマーク済みページ番号のセットを SharedPreferences に保存する。
Future<void> saveBookmarks(String filePath, Set<int> pages) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(bookmarkKey(filePath), jsonEncode(pages.toList()));
}
