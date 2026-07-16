import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// ローカルPush通知を管理するサービス。
///
/// ## 使い方
/// 1. `main()` で `NotificationService.initialize()` を呼ぶ
/// 2. 通知を送りたいタイミングで `show()` または `schedule()` を呼ぶ
/// 3. 権限が未付与の場合は `requestPermissions()` でリクエストする
///
/// ## schedule() の注意
/// AlarmManager / zonedSchedule ではなく Future.delayed + show() で実装しているため、
/// アプリが強制終了されると通知は届かない。POC 用途では問題ない。
class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static Timer? _scheduleTimer;
  static DateTime? _scheduledAt;

  /// 通知アクションID: ダウンロードボタン
  static const actionDownload = 'action_download';

  /// iOS 用通知カテゴリID（ダウンロードアクション付き）
  static const _categoryWithDownload = 'jal_content_download';

  /// 現在スケジュール中の通知時刻。未設定または発火済みなら null。
  static DateTime? get scheduledAt => _scheduledAt;

  static const _channelId = 'jal_app_notification';
  static const _channelName = 'アプリ通知';
  static const _channelDesc = 'JAL機内誌アプリからのお知らせ';

  /// [downloadUrl] が非 null のときはダウンロードアクションボタン付きの詳細を返す。
  static NotificationDetails _buildDetails({bool withDownload = false}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        actions: withDownload
            ? [
                const AndroidNotificationAction(
                  actionDownload,
                  'ダウンロード',
                  showsUserInterface: true,
                  cancelNotification: true,
                ),
              ]
            : null,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: withDownload ? _categoryWithDownload : null,
      ),
    );
  }

  /// アプリ起動時に一度呼び出す。
  ///
  /// [onTap]    : 通知本体タップ時のコールバック（payload が渡される）
  /// [onAction] : アクションボタンタップ時のコールバック（actionId, payload が渡される）
  static Future<void> initialize({
    void Function(String? payload)? onTap,
    void Function(String actionId, String? payload)? onAction,
  }) async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          _categoryWithDownload,
          actions: [
            DarwinNotificationAction.plain(
              actionDownload,
              'ダウンロード',
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
    );
    await _plugin.initialize(
      InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (response) {
        debugPrint(
          '[Notification] response: actionId=${response.actionId}, payload=${response.payload}',
        );
        final actionId = response.actionId;
        if (actionId != null) {
          onAction?.call(actionId, response.payload);
        } else {
          onTap?.call(response.payload);
        }
      },
    );
  }

  /// 通知権限をリクエストする。許可済みなら true を返す。
  /// iOS: システムダイアログを表示。
  /// Android 13+: POST_NOTIFICATIONS 権限をリクエスト。
  static Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final result = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return result ?? false;
    }
    if (Platform.isAndroid) {
      final result = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return result ?? false;
    }
    return false;
  }

  /// 即時通知を表示する。
  ///
  /// [downloadUrl] を指定すると通知に「ダウンロード」アクションボタンが付き、
  /// payload としてダウンロードURLが埋め込まれる。
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? downloadUrl,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      _buildDetails(withDownload: downloadUrl != null),
      payload: downloadUrl ?? payload,
    );
    debugPrint('[Notification] shown: id=$id, title=$title');
  }

  /// [scheduledDate] に通知をスケジュールする。
  ///
  /// AlarmManager (zonedSchedule) を使わず Future.delayed + show() で実装する。
  /// これにより Android の PendingIntent / AlarmManager 起因のフリーズ・クラッシュを回避できる。
  ///
  /// [downloadUrl] を指定すると通知に「ダウンロード」アクションボタンが付く。
  static Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
    String? downloadUrl,
  }) async {
    _scheduleTimer?.cancel();
    final delay = scheduledDate.difference(DateTime.now());
    final effectiveDelay = delay.isNegative ? Duration.zero : delay;
    _scheduledAt = scheduledDate;
    _scheduleTimer = Timer(effectiveDelay, () async {
      _scheduledAt = null;
      await show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        downloadUrl: downloadUrl,
      );
    });
    debugPrint(
      '[Notification] scheduled: id=$id, delay=${effectiveDelay.inSeconds}s, at=${scheduledDate.toIso8601String()}',
    );
  }

  /// 指定 ID の通知をキャンセルする。
  static Future<void> cancel(int id) async {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _scheduledAt = null;
    await _plugin.cancel(id);
    debugPrint('[Notification] cancelled: id=$id');
  }

  /// スケジュール済みタイマーと未送信通知をすべてキャンセルする。
  static Future<void> cancelAll() async {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _scheduledAt = null;
    await _plugin.cancelAll();
    debugPrint('[Notification] all cancelled');
  }

  /// スケジュール済みの未送信通知一覧を返す（plugin 側に登録されたもののみ）。
  static Future<List<PendingNotificationRequest>> pendingNotifications() =>
      _plugin.pendingNotificationRequests();
}
