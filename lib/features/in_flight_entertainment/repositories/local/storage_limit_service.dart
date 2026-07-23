import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PDF保存容量の上限管理サービス。
///
/// SharedPreferences に下記スキーマで保存する。
///   { filename: { "b": bytes, "cid": contentId, "lat": lastAccessedAt_ms } }
///
/// 旧フォーマット（{ filename: bytes_int }）は初回読み込み時に自動マイグレーション。
class StorageLimitService {
  StorageLimitService._();

  static const _keyLimit = 'storage_limit_bytes';
  static const _keyUsage = 'storage_usage_json';

  /// デフォルト上限: 500 MB
  static const defaultLimitBytes = 500 * 1024 * 1024;

  // ── 設定上限 ──────────────────────────────────────────────────────────────

  static Future<int> getLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLimit) ?? defaultLimitBytes;
  }

  static Future<void> setLimit(int bytes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLimit, bytes);
    debugPrint('[Storage] limit set: ${formatBytes(bytes)}');
  }

  // ── 使用量 ────────────────────────────────────────────────────────────────

  static Future<int> getTotalUsage() async {
    final map = await _loadMap();
    return _sumBytes(map);
  }

  // ── ダウンロードライフサイクル ───────────────────────────────────────────

  /// 上限超過なら `({usage, limit})` を返す。問題なければ null を返す。
  static Future<({int usage, int limit})?> checkBeforeDownload() async {
    final prefs = await SharedPreferences.getInstance();
    final limit = prefs.getInt(_keyLimit) ?? defaultLimitBytes;
    final map = await _loadMap();
    final usage = _sumBytes(map);
    if (usage >= limit) return (usage: usage, limit: limit);
    return null;
  }

  /// ダウンロード完了後にファイルサイズ・コンテンツIDを DB に記録する。
  /// lastAccessedAt はダウンロード完了時刻で初期化する。
  static Future<void> recordFile(
      String filename, int bytes, String contentId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _loadMap();
    map[filename] = {
      'b': bytes,
      'cid': contentId,
      'lat': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(_keyUsage, jsonEncode(map));
    debugPrint('[Storage] recorded: $filename = ${formatBytes(bytes)}');
  }

  /// PDF を開いたときに lastAccessedAt を更新する。
  static Future<void> recordAccess(String filename) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _loadMap();
    final entry = map[filename];
    if (entry == null) return;
    map[filename] = {
      ...Map<String, dynamic>.from(entry as Map),
      'lat': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(_keyUsage, jsonEncode(map));
  }

  /// ファイル削除時に DB から除外する。
  static Future<void> removeFile(String filename) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _loadMap();
    map.remove(filename);
    await prefs.setString(_keyUsage, jsonEncode(map));
    debugPrint('[Storage] removed: $filename');
  }

  // ── LRU 自動クリーンアップ ───────────────────────────────────────────────

  /// 上限超過時に古い・期限切れのキャッシュを自動削除する。
  ///
  /// 削除優先度:
  ///   1. マスター JSON の availableTo が過去になった期限切れファイル
  ///   2. lastAccessedAt が古い順（LRU）
  ///
  /// - [expirationByContentId]: contentId → availableTo のマップ（マスターJSONから生成）
  /// - [dir]: PDF 保存ディレクトリ
  /// - [now]: 判定基準時刻（省略時は DateTime.now()）
  ///
  /// 戻り値: 削除したファイル名のリスト
  static Future<List<String>> autoCleanup({
    required Map<String, DateTime?> expirationByContentId,
    required Directory dir,
    DateTime? now,
  }) async {
    final effectiveNow = now ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final limit = prefs.getInt(_keyLimit) ?? defaultLimitBytes;
    final map = await _loadMap();
    final deleted = <String>[];

    // Step 1: 期限切れファイルをすべて削除
    for (final filename in List<String>.from(map.keys)) {
      final entry = map[filename] as Map<String, dynamic>;
      final cid = entry['cid'] as String? ?? filename.split('_').first;
      final expiry = expirationByContentId[cid];
      if (expiry != null && effectiveNow.isAfter(expiry)) {
        final file = File('${dir.path}/$filename');
        if (await file.exists()) await file.delete();
        map.remove(filename);
        deleted.add(filename);
        debugPrint('[Storage] auto-deleted (expired): $filename');
      }
    }

    // Step 2: まだ上限超過なら LRU 順に削除
    var usage = _sumBytes(map);
    if (usage >= limit) {
      final sorted = map.entries.toList()
        ..sort((a, b) {
          final aLat =
              (a.value as Map<String, dynamic>)['lat'] as int? ?? 0;
          final bLat =
              (b.value as Map<String, dynamic>)['lat'] as int? ?? 0;
          return aLat.compareTo(bLat);
        });
      for (final entry in sorted) {
        if (usage < limit) break;
        final filename = entry.key;
        final file = File('${dir.path}/$filename');
        if (await file.exists()) await file.delete();
        usage -= (entry.value as Map<String, dynamic>)['b'] as int? ?? 0;
        map.remove(filename);
        deleted.add(filename);
        debugPrint('[Storage] auto-deleted (LRU): $filename');
      }
    }

    await prefs.setString(_keyUsage, jsonEncode(map));
    return deleted;
  }

  // ── 補正 ─────────────────────────────────────────────────────────────────

  /// ディレクトリを走査して DB と実ファイルの差分を補正する。
  static Future<void> syncWithDirectory(Directory dir) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _loadMap();

    final toRemove = <String>[];
    for (final key in map.keys) {
      final file = File('${dir.path}/$key');
      if (file.existsSync()) {
        final entry = Map<String, dynamic>.from(map[key] as Map);
        entry['b'] = file.lengthSync();
        map[key] = entry;
      } else {
        toRemove.add(key);
      }
    }
    for (final k in toRemove) {
      map.remove(k);
    }
    await prefs.setString(_keyUsage, jsonEncode(map));
    debugPrint('[Storage] synced: ${map.length} files tracked');
  }

  // ── ユーティリティ ───────────────────────────────────────────────────────

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // ── 内部ヘルパー ─────────────────────────────────────────────────────────

  /// SharedPreferences から DB を読み込む。旧フォーマットを自動マイグレーションする。
  static Future<Map<String, dynamic>> _loadMap() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyUsage);
    if (json == null) return {};
    final raw = jsonDecode(json) as Map<String, dynamic>;

    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (entry.value is int) {
        // 旧フォーマット移行: ファイル名の先頭セグメントを contentId として扱う
        result[entry.key] = {
          'b': entry.value as int,
          'cid': entry.key.split('_').first,
          'lat': 0, // アクセス履歴なし → LRU で最優先に削除される
        };
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  static int _sumBytes(Map<String, dynamic> map) {
    return map.values.fold<int>(0, (sum, v) {
      if (v is Map) return sum + ((v['b'] as int?) ?? 0);
      return sum;
    });
  }
}
