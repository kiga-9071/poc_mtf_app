import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/pdf_content.dart';

// iOS では localhost が ::1 (IPv6) に解決されてコネクション拒否になるため
// サーバーのバインドアドレス 127.0.0.1 (IPv4) を直接指定する。
const _kContentsServerUrl = 'http://127.0.0.1:8765/contents.json';
const _kCacheJsonKey = 'content_master_json';
const _kFetchedAtKey = 'content_master_fetched_at_ms';
const _kTrustedTimeKey = 'content_master_trusted_time_ms';

/// サーバーから取得・ローカルキャッシュされたコンテンツマスター情報。
class ContentMaster {
  const ContentMaster({
    required this.contents,
    this.trustedTime,
    this.lastFetchedAt,
  });

  /// langCode → コンテンツ一覧のマップ
  final Map<String, List<PdfContent>> contents;

  /// サーバーの Date ヘッダーから得た信頼できる時刻。
  /// オフライン時や取得失敗時は null。
  final DateTime? trustedTime;

  /// マスターデータの最終取得日時
  final DateTime? lastFetchedAt;

  /// 指定言語コードのコンテンツ一覧を返す（存在しなければ ja にフォールバック）。
  List<PdfContent> contentsFor(String langCode) =>
      contents[langCode] ?? contents['ja'] ?? [];

  /// 表示期間チェックに使用する「現在時刻」。
  /// サーバー時刻が取得できていればそれを、なければ端末時刻を使用する。
  DateTime get now => trustedTime ?? DateTime.now();
}

final contentMasterProvider =
    StateNotifierProvider<ContentMasterNotifier, AsyncValue<ContentMaster>>(
  (ref) => ContentMasterNotifier(),
);

class ContentMasterNotifier extends StateNotifier<AsyncValue<ContentMaster>> {
  ContentMasterNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));

  Future<void> _init() async {
    // キャッシュをロードして即時表示（ネットワーク待ちの間もコンテンツを見せる）
    final cached = await _loadFromCache();
    if (cached != null && state is AsyncLoading) {
      state = AsyncValue.data(cached);
    }
    await _fetchAndUpdate();
  }

  /// アプリ起動・復帰時に呼び出してマスターデータを最新化する。
  Future<void> refresh() async {
    await _fetchAndUpdate();
  }

  Future<void> _fetchAndUpdate() async {
    await _loadFromServer();
  }

  Future<void> _loadFromServer() async {
    try {
      final response = await _dio.get<String>(
        _kContentsServerUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = response.data as String;

      // Date ヘッダーを信頼できる時刻として使用する
      DateTime? trustedTime;
      final dateHeader = response.headers.value('date');
      if (dateHeader != null) {
        try {
          trustedTime = HttpDate.parse(dateHeader);
        } catch (_) {}
      }
      trustedTime ??= DateTime.now();

      final now = DateTime.now();
      final master = _parse(raw, trustedTime: trustedTime, lastFetchedAt: now);
      state = AsyncValue.data(master);
      await _saveToCache(
        raw,
        trustedTimeMs: trustedTime.millisecondsSinceEpoch,
        fetchedAtMs: now.millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('[ContentMaster] server fetch error: $e');
      // サーバーに接続できない場合は assets の contents.json を直接読み込む
      await _loadFromBundle();
    }
  }

  /// assets バンドルから直接 contents.json を読み込む。
  /// サーバー未起動時（Android 起動直後など）のフォールバック。
  Future<void> _loadFromBundle() async {
    try {
      final raw = await rootBundle.loadString(
        'packages/mock_server/assets/contents.json',
      );
      final now = DateTime.now();
      final master = _parse(raw, trustedTime: now, lastFetchedAt: now);
      if (state is AsyncLoading || state is AsyncError) {
        state = AsyncValue.data(master);
      }
      debugPrint('[ContentMaster] loaded from bundle (server unavailable)');
    } catch (e, st) {
      debugPrint('[ContentMaster] bundle load error: $e');
      if (state is AsyncLoading) state = AsyncValue.error(e, st);
    }
  }

  ContentMaster _parse(
    String raw, {
    required DateTime? trustedTime,
    required DateTime? lastFetchedAt,
  }) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final contents = <String, List<PdfContent>>{};
    for (final key in json.keys) {
      contents[key] = (json[key] as List<dynamic>)
          .map((e) => PdfContent.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return ContentMaster(
      contents: contents,
      trustedTime: trustedTime,
      lastFetchedAt: lastFetchedAt,
    );
  }

  Future<ContentMaster?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCacheJsonKey);
      if (raw == null) return null;
      final trustedTimeMs = prefs.getInt(_kTrustedTimeKey);
      final fetchedAtMs = prefs.getInt(_kFetchedAtKey);
      return _parse(
        raw,
        trustedTime: trustedTimeMs != null
            ? DateTime.fromMillisecondsSinceEpoch(trustedTimeMs)
            : null,
        lastFetchedAt: fetchedAtMs != null
            ? DateTime.fromMillisecondsSinceEpoch(fetchedAtMs)
            : null,
      );
    } catch (e) {
      debugPrint('[ContentMaster] cache load error: $e');
      return null;
    }
  }

  Future<void> _saveToCache(
    String raw, {
    required int? trustedTimeMs,
    required int fetchedAtMs,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCacheJsonKey, raw);
      await prefs.setInt(_kFetchedAtKey, fetchedAtMs);
      if (trustedTimeMs != null) {
        await prefs.setInt(_kTrustedTimeKey, trustedTimeMs);
      } else {
        await prefs.remove(_kTrustedTimeKey);
      }
    } catch (e) {
      debugPrint('[ContentMaster] cache save error: $e');
    }
  }
}
