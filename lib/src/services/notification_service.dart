import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// ローカルPush通知を管理するサービス。
///
/// ## 使い方
/// 1. `main()` で `NotificationService.initialize()` を呼ぶ
/// 2. 通知を送りたいタイミングで `show()` または `schedule()` を呼ぶ
/// 3. 権限が未付与の場合は `requestPermissions()` でリクエストする
///
/// ## schedule() の動作
/// OS レベルの zonedSchedule (iOS: UNCalendarNotificationTrigger, Android: AlarmManager)
/// を使用するため、アプリがキルされていても通知が届く。
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
        presentBanner: true,
        presentList: true,
        categoryIdentifier: withDownload ? _categoryWithDownload : null,
      ),
    );
  }

  static const _androidChannel = MethodChannel('app.notification.android');

  /// デバイスのタイムゾーン識別子（IANA 形式）を取得して tz.local に設定する。
  /// zonedSchedule でデバイス現地時刻通りに通知を登録するために必要。
  /// tz.local のデフォルトは UTC のため、明示的に設定しないと時刻がずれる。
  static Future<void> _initLocalTimezone() async {
    try {
      final tzName = await const MethodChannel('app.pdf.thumbnail')
          .invokeMethod<String>('getTimezone');
      if (tzName != null) {
        tz.setLocalLocation(tz.getLocation(tzName));
        debugPrint('[Notification] timezone: $tzName');
      }
    } catch (e) {
      debugPrint('[Notification] timezone init failed: $e');
    }
  }

  /// アプリ起動時に一度呼び出す。
  ///
  /// [onTap]    : 通知本体タップ時のコールバック（payload が渡される）
  /// [onAction] : アクションボタンタップ時のコールバック（actionId, payload が渡される）
  static Future<void> initialize({
    void Function(String? payload)? onTap,
    void Function(String actionId, String? payload)? onAction,
  }) async {
    // zonedSchedule に必要なタイムゾーンデータを初期化する。
    tz_data.initializeTimeZones();
    // デバイスのローカルタイムゾーンを tz.local に設定する（iOS/Android 共通）。
    // これをしないと tz.local が UTC になり、zonedSchedule の時刻がずれる。
    await _initLocalTimezone();

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

    void handleResponse(NotificationResponse response) {
      debugPrint(
        '[Notification] response: actionId=${response.actionId}, payload=${response.payload}',
      );
      final actionId = response.actionId;
      if (actionId != null) {
        onAction?.call(actionId, response.payload);
      } else {
        onTap?.call(response.payload);
      }
    }

    await _plugin.initialize(
      InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: handleResponse,
    );

    // アプリがキル状態から通知タップで起動した場合の処理。
    // onDidReceiveNotificationResponse はキル状態では呼ばれないため、
    // getNotificationAppLaunchDetails() で起動原因を確認する。
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final response = launchDetails!.notificationResponse;
      if (response != null) {
        debugPrint('[Notification] launched from notification: ${response.payload}');
        handleResponse(response);
      }
    }
  }

  /// 通知権限をリクエストする。許可済みなら true を返す。
  /// iOS: システムダイアログを表示。
  /// Android 13+: POST_NOTIFICATIONS 権限をリクエスト。
  /// Android 12+: SCHEDULE_EXACT_ALARM 権限と電池最適化除外もリクエストする。
  static Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final result = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return result ?? false;
    }
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      // Android 13+: 通知表示の権限
      final notifResult = await androidPlugin?.requestNotificationsPermission();

      // Android 12+: exactAllowWhileIdle に必要な正確なアラーム権限。
      // 未許可の場合はシステム設定画面を開く。
      final canExact = await androidPlugin?.canScheduleExactNotifications();
      if (canExact == false) {
        await androidPlugin?.requestExactAlarmsPermission();
      }

      // 電池最適化除外をリクエスト（OEM の省電力によるアラームキャンセルを防ぐ）。
      // 未除外の場合はシステムダイアログを表示する。
      try {
        await _androidChannel
            .invokeMethod('requestBatteryOptimizationExemption');
      } catch (_) {}

      return notifResult ?? false;
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
  /// OS レベルの zonedSchedule (iOS: UNCalendarNotificationTrigger,
  /// Android: AlarmManager) を使用するため、アプリがキルされていても通知が届く。
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
    // 旧実装（Timer）が残っていればキャンセルし、同一 ID の登録済み通知も上書き
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    await _plugin.cancel(id);

    // 過去時刻はそのまま即時発火
    if (scheduledDate.isBefore(DateTime.now())) {
      _scheduledAt = null;
      await show(
          id: id, title: title, body: body, payload: payload, downloadUrl: downloadUrl);
      return;
    }

    _scheduledAt = scheduledDate;
    final delayMs = scheduledDate.difference(DateTime.now()).inMilliseconds;

    if (Platform.isAndroid) {
      // Android: AlarmManager + LocalNotificationReceiver で直接スケジュール。
      // flutter_local_notifications の zonedSchedule は kill 状態でエンジン依存のため使わない。
      try {
        await _androidChannel.invokeMethod('scheduleLocalNotification', {
          'id': id,
          'title': title,
          'body': body,
          'delayMs': delayMs < 1000 ? 1000 : delayMs,
        });
      } catch (e) {
        _scheduledAt = null;
        debugPrint('[Notification] Android schedule failed: $e');
        rethrow;
      }
    } else {
      // iOS: zonedSchedule → UNCalendarNotificationTrigger（OS 管理、kill 後も発火）
      final tzDate = tz.TZDateTime.from(scheduledDate, tz.local);
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          tzDate,
          _buildDetails(withDownload: downloadUrl != null),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: downloadUrl ?? payload,
        );
      } catch (e) {
        _scheduledAt = null;
        debugPrint('[Notification] iOS zonedSchedule failed: $e');
        rethrow;
      }
    }
    debugPrint(
      '[Notification] scheduled: id=$id, at=${scheduledDate.toIso8601String()}',
    );
  }

  /// 指定 ID の通知をキャンセルする。
  static Future<void> cancel(int id) async {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _scheduledAt = null;
    if (Platform.isAndroid) {
      await _androidChannel.invokeMethod('cancelLocalNotification', {'id': id});
    } else {
      await _plugin.cancel(id);
    }
    debugPrint('[Notification] cancelled: id=$id');
  }

  /// スケジュール済みタイマーと未送信通知をすべてキャンセルする。
  static Future<void> cancelAll() async {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _scheduledAt = null;
    if (Platform.isAndroid) {
      // スケジュール中の固定 ID（200）をキャンセル
      await _androidChannel
          .invokeMethod('cancelLocalNotification', {'id': 200});
    }
    await _plugin.cancelAll();
    debugPrint('[Notification] all cancelled');
  }

  /// スケジュール済みの未送信通知一覧を返す（plugin 側に登録されたもののみ）。
  static Future<List<PendingNotificationRequest>> pendingNotifications() =>
      _plugin.pendingNotificationRequests();
}
