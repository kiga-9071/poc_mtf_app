# pdf_app

PDFの描画や技術検証を行うためのPoCアプリです。  
PDF コンテンツの閲覧・ダウンロード・通知などをデモする Flutter アプリです。

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

## 画面構成

| ルート | 画面 | 概要 |
|---|---|---|
| `/` | コンテンツ一覧 | SKYWARD / JAL SHOP / YouTube の 3 タブ |
| `/backnumber` | バックナンバー | 全コンテンツ or ダウンロード済みの一覧 |
| `/viewer` | PDF ビューア | PDF の閲覧・検索・ブックマーク・TTS |
| `/webview` | インアプリ WebView | 外部記事・ショップページの表示 |

### コンテンツ一覧（`/`）

- **SKYWARD タブ**: 最新号のフィーチャーカード + Pick UP 記事（カテゴリフィルター付き）+ バナー広告
- **JAL SHOP タブ**: 機内販売商品の一覧（WebView へ遷移）
- **Youtube タブ**: JAL 公式 YouTube 動画のサムネイル一覧（WebView へ遷移）

### PDF ビューア（`/viewer`）

- ページ横スワイプ
- ピンチズーム・パン
- キーワード検索・ハイライト
- テキスト選択・コピー
- ブックマーク・メモ（ページ単位）
- 目次・内部リンク・外部リンク
- サムネイルストリップ・ミニマップ
- 音声読み上げ（TTS）: OCR で取得したテキストを読み上げ
- スクリーンショット・録画抑止（`preventCapture: true` 時）

## 主な機能

### コンテンツ管理

| 機能 | 概要 |
|---|---|
| アプリ内 PDF サーバー | `mock_server` パッケージが `127.0.0.1:8765` でコンテンツを配信 |
| バックグラウンドダウンロード | `background_downloader` で PDF をローカルに保存 |
| 差し替えダウンロード | `lastUpdatedAt` を比較し、マスターが新しい場合は自動で再ダウンロード |
| ストレージ上限管理 | デフォルト 500 MB。超過時は LRU で古いファイルを自動削除。上限は設定ダイアログから変更可 |
| プレビューキャッシュ | ダウンロード済み PDF の 1 ページ目サムネイルをローカルにキャッシュ |

### 通知

- ローカル Push 通知（`flutter_local_notifications`）
- 即時送信・時刻指定スケジュール送信
- 通知アクションからワンタップでダウンロード開始
- 通知タップでバックナンバー画面へ遷移

### その他

- **ダークモード**: ライト / ダーク / システム追従
- **日本語 / 英語** UI 切替
- **Firebase Analytics**: 画面遷移・タブ切替・コンテンツ操作をログ記録
- **iOS WebKit ウォームアップ**: 初回 WebView 表示時の遅延を削減

## 開発者向けメニュー（右上 `⋮`）

| メニュー項目 | 内容 |
|---|---|
| 通知テスト | 即時 or スケジュール通知の送信テスト |
| ストレージ設定 | 上限値の確認・変更 |
| ストレージを初期化 | ダウンロード済み PDF・SharedPreferences を全削除 |
