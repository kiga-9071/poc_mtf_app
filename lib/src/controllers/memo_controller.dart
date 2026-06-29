import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

String _memoKey(String filePath) => 'memo_${filePath.hashCode}';

/// SharedPreferences からページ番号→メモテキストのマップを読み込む。
Future<Map<int, String>> loadMemos(String filePath) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_memoKey(filePath));
  if (raw == null) return {};
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded.map((k, v) => MapEntry(int.parse(k), v as String));
}

/// ページ番号→メモテキストのマップを SharedPreferences に保存する。
Future<void> saveMemos(String filePath, Map<int, String> memos) async {
  final prefs = await SharedPreferences.getInstance();
  final encoded = memos.map((k, v) => MapEntry(k.toString(), v));
  await prefs.setString(_memoKey(filePath), jsonEncode(encoded));
}
