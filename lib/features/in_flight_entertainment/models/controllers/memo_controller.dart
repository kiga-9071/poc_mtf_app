// PDFビューアのページメモ（ページ番号→テキストのマップ）を SharedPreferences で永続化するユーティリティ。
//
// メモはファイルパスのハッシュをキーとして保存するため、
// 異なるPDFファイルのメモが互いに干渉しない。
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// ファイルパスに対応するメモ保存キーを生成する。
/// ファイルパスをハッシュ化してキーの重複を防ぐ。
String _memoKey(String filePath) => 'memo_${filePath.hashCode}';

/// SharedPreferences からページ番号→メモテキストのマップを読み込む。
Future<Map<int, String>> loadMemos(String filePath) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_memoKey(filePath));
  if (raw == null) return {};
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  // JSON のキーは必ず String 型のため、ページ番号へ復元するために int.parse が必要
  return decoded.map((k, v) => MapEntry(int.parse(k), v as String));
}

/// ページ番号→メモテキストのマップを SharedPreferences に保存する。
Future<void> saveMemos(String filePath, Map<int, String> memos) async {
  final prefs = await SharedPreferences.getInstance();
  final encoded = memos.map((k, v) => MapEntry(k.toString(), v));
  await prefs.setString(_memoKey(filePath), jsonEncode(encoded));
}
