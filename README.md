# pdf_app

pdfrx を使用した PDF ビューア PoC アプリです。  
開発用の PDF 配信はアプリ内サーバー（`127.0.0.1:8765`）で行うため、外部 Python サーバーや `adb reverse` は不要です。

## 動作環境

- Flutter 3.44.0 以上 / Dart 3.12.0 以上
- FVM を使用する場合: `fvm use 3.44.2`

## セットアップ

```bash
flutter pub get
# FVM の場合
fvm flutter pub get
```

## アプリ起動

```bash
# iOS シミュレータ
flutter run -d ios
# FVM の場合
fvm flutter run -d ios

# Android エミュレータ / 実機
flutter run -d android
# FVM の場合
fvm flutter run -d android
```

### 接続済みデバイスを選択

```bash
flutter devices          # デバイス一覧を確認
flutter run -d <device-id>
# FVM の場合
fvm flutter devices
fvm flutter run -d <device-id>
```

## ソースモード切替

アプリ下部のセグメントボタンで PDF の取得元を切り替えられます。

| モード | 取得元 | 追加セットアップ |
|---|---|---|
| **サーバー** | `http://127.0.0.1:8765/`（アプリ内サーバー） | 不要 |
| **ローカル** | `packages/mock_server/assets/pdfs/` の同梱アセット | 不要 |

## 主な機能

- PDF のページ表示（横スワイプ）
- ピンチズーム・パン操作
- キーワード検索・ハイライト
- テキスト選択・コピー
- ブックマーク・メモ（ページ単位）
- 目次・内部リンク・外部リンク
- ダークモード
- 日本語 / 英語 UI 切替
