import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase Analytics へのイベント送信を一元管理するサービス。
///
/// すべてのメソッドは fire-and-forget（await 不要）で呼び出す。
/// 失敗しても UI に影響を与えないよう内部でエラーを握り潰す。
class AnalyticsService {
  AnalyticsService._();

  static final _analytics = FirebaseAnalytics.instance;

  // ── PDF ダウンロード ────────────────────────────────────────────────────────

  /// PDFダウンロードを開始したとき。
  static void logPdfDownloadStart({
    required String contentId,
    required String contentTitle,
  }) =>
      _send('pdf_download_start', {
        'content_id': contentId,
        'content_title': _trim(contentTitle),
      });

  /// PDFダウンロードが完了したとき。
  static void logPdfDownloadComplete({
    required String contentId,
    required String contentTitle,
  }) =>
      _send('pdf_download_complete', {
        'content_id': contentId,
        'content_title': _trim(contentTitle),
      });

  /// PDFダウンロードが失敗したとき。
  static void logPdfDownloadFailed({
    required String contentId,
    required String contentTitle,
    required String reason,
  }) =>
      _send('pdf_download_failed', {
        'content_id': contentId,
        'content_title': _trim(contentTitle),
        'reason': _trim(reason),
      });

  /// PDFダウンロードをキャンセルしたとき。
  static void logPdfDownloadCancelled({
    required String contentId,
    required String contentTitle,
  }) =>
      _send('pdf_download_cancelled', {
        'content_id': contentId,
        'content_title': _trim(contentTitle),
      });

  // ── PDF ビューア ────────────────────────────────────────────────────────────

  /// PDFビューアを起動したとき。
  static void logPdfOpen({
    required String contentId,
    required String contentTitle,
  }) =>
      _send('pdf_open', {
        'content_id': contentId,
        'content_title': _trim(contentTitle),
      });

  /// PDFビューアでページを表示したとき。
  static void logPdfPageView({
    required String contentId,
    required int pageNumber,
  }) =>
      _send('pdf_page_view', {
        'content_id': contentId,
        'page_number': pageNumber,
      });

  /// PDFビューアを閉じたとき（戻るボタン）。
  static void logPdfClose({
    required String contentId,
    required int lastPage,
  }) =>
      _send('pdf_close', {
        'content_id': contentId,
        'last_page': lastPage,
      });

  // ── PDF 削除 ────────────────────────────────────────────────────────────────

  /// ダウンロード済みPDFを削除したとき。
  static void logPdfDelete({
    required String contentId,
    required String contentTitle,
  }) =>
      _send('pdf_delete', {
        'content_id': contentId,
        'content_title': _trim(contentTitle),
      });

  // ── 画面遷移 ────────────────────────────────────────────────────────────────

  /// コンテンツ一覧のタブを切り替えたとき。
  /// [tabName]: 'skyward' | 'jal_shop' | 'youtube'
  static void logContentTabSwitch({required String tabName}) =>
      _send('content_tab_switch', {'tab_name': tabName});

  /// バックナンバーページを開いたとき。
  static void logBacknumberPageView() =>
      _send('backnumber_page_view', {});

  /// バックナンバーのタブを切り替えたとき。
  /// [tabName]: 'all' | 'downloaded'
  static void logBacknumberTabSwitch({required String tabName}) =>
      _send('backnumber_tab_switch', {'tab_name': tabName});

  /// Webコンテンツ（ChromeSafariBrowser）を開いたとき。
  static void logWebContentOpen({
    required String contentId,
    required String contentTitle,
  }) =>
      _send('web_content_open', {
        'content_id': contentId,
        'content_title': _trim(contentTitle),
      });

  // ── 内部ユーティリティ ──────────────────────────────────────────────────────

  /// Firebase Analytics のパラメータ値上限（100文字）に合わせてトリムする。
  static String _trim(String value) =>
      value.length > 100 ? value.substring(0, 100) : value;

  static void _send(String name, Map<String, Object> parameters) {
    _analytics.logEvent(name: name, parameters: parameters).catchError((e) {
      debugPrint('[Analytics] failed to log $name: $e');
    });
  }
}
