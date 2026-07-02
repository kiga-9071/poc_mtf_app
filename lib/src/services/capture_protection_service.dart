import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_protector/screen_protector.dart';

/// OS レベルのキャプチャ（スクリーンショット・録画）抑止を管理するサービス。
///
/// Android: MainActivity に実装した MethodChannel 経由で FLAG_SECURE を直接操作する。
///   FLAG_SECURE はスクリーンショット・画面録画・タスクスイッチャーのサムネイル
///   すべてを OS レベルで抑止する。
/// iOS: screen_protector の UITextField トリック（スクリーンショット抑止）と
///   バックグラウンド時の黒オーバーレイ（アプリスイッチャーでの内容漏洩防止）を使用する。
///   ※ iOS はユーザーによるスクリーンショットを完全に防ぐことはできない。
class CaptureProtectionService {
  CaptureProtectionService._();

  static const _channel =
      MethodChannel('jp.co.pdf.example.dev/capture_protection');

  static Future<void> enable() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('enable');
    } else if (Platform.isIOS) {
      await ScreenProtector.preventScreenshotOn();
      await ScreenProtector.protectDataLeakageWithColor(Colors.black);
    }
  }

  static Future<void> disable() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('disable');
    } else if (Platform.isIOS) {
      await ScreenProtector.preventScreenshotOff();
      await ScreenProtector.protectDataLeakageWithColorOff();
    }
  }
}
