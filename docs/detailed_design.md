# 詳細設計書

## 1. アプリ概要

| 項目 | 内容 |
|---|---|
| アプリ名 | pdf_app |
| 位置づけ | 機内エンタメ（IFE: In-Flight Entertainment）PoC |
| 対象プラットフォーム | iOS / Android |
| Flutter バージョン | 3.44.0 以上 |
| Dart SDK | >=3.12.0 <4.0.0 |

JAL の機内誌 SKYWARD を中心に、PDF コンテンツの閲覧・ダウンロード・通知・分析をデモする Flutter アプリ。  
コンテンツ配信はアプリ内 HTTP サーバー（`mock_server` パッケージ）で完結し、外部サーバーを必要としない。

---

## 2. アーキテクチャ

### 2.1 ディレクトリ構成

```
lib/
├── main.dart                          # エントリーポイント・ルーティング定義・テーマ設定
├── core/
│   └── utils/
│       └── l10n.dart                  # 多言語文字列管理（ja/en）
├── features/
│   ├── in_flight_entertainment/
│   │   ├── constants/
│   │   │   └── pdf_viewer_constants.dart  # ビューア共通定数・カラーフィルター
│   │   ├── models/
│   │   │   ├── controllers/
│   │   │   │   ├── bookmark_controller.dart       # ブックマーク永続化
│   │   │   │   ├── content_master_controller.dart # コンテンツマスター取得・キャッシュ
│   │   │   │   ├── memo_controller.dart           # メモ永続化
│   │   │   │   └── search_controller.dart         # PDFキーワード検索
│   │   │   └── entities/
│   │   │       ├── pdf_content.dart   # コンテンツデータモデル
│   │   │       ├── search_match.dart  # 検索ヒット情報（typedef record）
│   │   │       └── viewer_args.dart   # ビューア遷移引数
│   │   ├── pages/
│   │   │   ├── backnumber_page.dart   # バックナンバー一覧画面
│   │   │   ├── content_list_page.dart # コンテンツ一覧画面（メイン）
│   │   │   └── pdf_viewer_page.dart   # PDFビューア画面
│   │   ├── repositories/
│   │   │   ├── local/
│   │   │   │   ├── pdf_document_cache.dart  # Pdfiumドキュメント事前オープンキャッシュ
│   │   │   │   ├── pdf_preview_cache.dart   # サムネイルディスクキャッシュ
│   │   │   │   └── storage_limit_service.dart # PDF保存容量上限管理
│   │   │   └── remote/
│   │   │       └── content_update_service.dart # バックグラウンド差し替えダウンロード
│   │   └── widgets/
│   │       ├── content_featured_card.dart  # フィーチャード大型カード
│   │       ├── content_list_card.dart      # テキスト中心のリストカード
│   │       ├── content_preview_card.dart   # サムネイル中心のグリッドカード
│   │       ├── pdf_link_overlay.dart       # PDFリンク透明ボタンオーバーレイ
│   │       ├── pdf_mini_map.dart           # ズーム時ミニマップ
│   │       ├── pdf_search_highlight.dart   # 検索ハイライトオーバーレイ
│   │       ├── pdf_search_nav_bar.dart     # 検索ナビゲーションバー
│   │       ├── pdf_side_drawer.dart        # サイドドロワー（目次・ブックマーク・検索）
│   │       ├── pdf_thumbnail_strip.dart    # 下部サムネイルストリップ
│   │       ├── pdf_top_bar.dart            # 上部カスタムバー
│   │       ├── pdf_tts_highlight.dart      # TTS読み上げハイライトオーバーレイ
│   │       ├── shop_tab.dart               # JAL SHOPタブ
│   │       ├── storage_limit_dialog.dart   # ストレージ容量ダイアログ群
│   │       └── youtube_tab.dart            # YouTube公式タブ
│   └── notification/
│       └── repositories/
│           └── notification_service.dart  # ローカルPush通知管理
├── shared/
│   ├── components/
│   │   ├── hooks/
│   │   │   ├── locale_controller.dart   # 表示言語の状態管理・永続化
│   │   │   └── theme_controller.dart    # テーマモードの状態管理・永続化
│   │   └── utils/
│   │       └── capture_protection_service.dart # キャプチャ抑止
│   └── features/
│       ├── analytics/
│       │   └── services/
│       │       └── analytics_service.dart # Firebase Analytics イベント送信
│       └── webview/
│           └── controllers/
│               └── webview_page.dart    # インアプリWebView画面

mock_server/                           # アプリ内HTTP配信サーバー（Dart package）
├── lib/
│   └── pdf_asset_server.dart          # PdfAssetServer（127.0.0.1:8765）
└── assets/
    ├── contents.json                  # コンテンツ定義マスター
    ├── pdfs/                          # 配信するPDFファイル群
    └── previews/                      # プレビュー画像（PNG）
```

### 2.2 状態管理

Riverpod（`hooks_riverpod`）を使用。すべてのプロバイダーは `ProviderScope` 下でグローバルに参照可能。

| プロバイダー | 型 | 役割 |
|---|---|---|
| `contentMasterProvider` | `StateNotifierProvider<ContentMasterNotifier, AsyncValue<ContentMaster>>` | コンテンツマスター JSON の取得・キャッシュ |
| `localeProvider` | `StateNotifierProvider<LocaleController, Locale>` | 表示言語（ja / en）の管理・永続化 |
| `themeModeProvider` | `StateNotifierProvider<ThemeController, ThemeMode>` | テーマモード（system / light / dark）の管理・永続化 |

PDF ビューア内の状態（ページ番号・ブックマーク・検索結果・TTS ステータスなど）は `flutter_hooks` の `useState` / `useMemoized` でローカル管理し、ビューア画面外へ露出しない。

### 2.3 ルーティング

`go_router` を使用。ルート定義は `main.dart` の `_router` で管理。

```
/              → ContentListPage（起動時の初期画面）
/backnumber    → BacknumberPage（バックナンバー一覧）
/viewer        → PdfViewerPage（PDFビューア、extra: ViewerArgs）
/webview       → WebViewPage（インアプリWebView、extra: String | ({url, showBackToList})）
```

**画面遷移フロー**

```
ContentListPage
  ├─ コンテンツカードタップ（PDF）   → /viewer
  ├─ コンテンツカードタップ（Web）   → ChromeSafariBrowser（アプリ外）
  ├─ Pick UP 記事カードタップ       → /webview（showBackToList: true）
  ├─ バナー広告タップ               → /webview
  ├─ AppBar「バックナンバー」       → /backnumber
  └─ JAL SHOP / YouTube タブ商品  → /webview

BacknumberPage
  └─ コンテンツカードタップ（PDF）   → /viewer

PdfViewerPage
  ├─ リンクオーバーレイ（外部URL）   → /webview（スタックプッシュ）
  └─ 戻るボタン                   → /（go_router pop or go('/')）

通知タップ → /backnumber
通知アクション（ダウンロード）→ バックグラウンドダウンロード開始
```

---

## 3. 画面設計

### 3.1 コンテンツ一覧画面（ContentListPage）

**ルート**: `/`

**役割**  
アプリのメイン画面。SKYWARD・JAL SHOP・YouTube の 3 タブでコンテンツを提示する。

**表示要素**

| 要素 | 内容 |
|---|---|
| AppBar | タイトル「機内を楽しむ」、テーマ切替・言語切替アイコン、メニュー（⋮） |
| TabBar | SKYWARD / JAL SHOP / Youtube【公式】の 3 タブ |
| **SKYWARD タブ** | 背景画像（diagonal_mask.png）+ スクロールビュー |
| フィーチャードカード | 最新号（category=「機内誌」）を `ContentFeaturedCard` で大きく表示 |
| Pick UP セクション | カテゴリフィルタータグ（2行）＋ バナー広告 ＋ コンテンツグリッド |
| カテゴリフィルター | 「旅・文化」「グルメ・お土産」「物語」「エンタメ」「JAL Stories」の5種。「旅・文化」は静的記事グリッド、他は `contents.json` のカテゴリで絞り込んだ `ContentPreviewCard` グリッド |
| バナー広告 | 全農チキンの画像広告。タップで外部 WebView へ遷移 |
| **JAL SHOP タブ** | `ShopTab`（機内販売商品一覧、タップで WebView） |
| **YouTube タブ** | `YoutubeTab`（公式動画一覧、タップで YouTube WebView） |
| メニュー（⋮） | 通知テスト / ストレージ設定 / ストレージを初期化 |

**主要なロジック**

- アプリ復帰（`AppLifecycleState.resumed`）時に `contentMasterProvider` を refresh し、ストレージ DB を実ファイルと同期（`StorageLimitService.syncWithDirectory`）
- `contentMasterProvider` のデータ更新を `ref.listen` で監視し、ダウンロード済みコンテンツの差し替えチェック（`ContentUpdateService.checkAndUpdateAll`）を実行
- タブ切替時に Firebase Analytics へ `content_tab_switch` イベントを送信

---

### 3.2 バックナンバー画面（BacknumberPage）

**ルート**: `/backnumber`

**役割**  
category が「機内誌」「In-flight Magazine」以外のすべてのコンテンツをバックナンバーとして一覧表示する。

**表示要素**

| 要素 | 内容 |
|---|---|
| AppBar | タイトル「バックナンバー」 |
| タブ切替（カスタム） | 「一覧」タブ / 「ダウンロード済み」タブ（カプセル型トグル） |
| コンテンツグリッド | `ContentPreviewCard` の 2 列グリッド |

**主要なロジック**

- 「ダウンロード済み」タブ: `buildSavePath()` でローカルファイルの存在を確認してフィルタリング
- アプリ復帰時に `contentMasterProvider` を refresh し `reloadKey` をインクリメント
- 画面表示時に `backnumber_page_view` イベントを Firebase Analytics に送信
- タブ切替時に `backnumber_tab_switch` イベントを送信

---

### 3.3 PDF ビューア画面（PdfViewerPage）

**ルート**: `/viewer`

**役割**  
ローカルに保存された PDF を表示するフル機能ビューア。

**受け取る引数（ViewerArgs）**

| プロパティ | 型 | 説明 |
|---|---|---|
| `filePath` | `String?` | 開くローカルファイルのパス（null = ファイル未選択） |
| `preventCapture` | `bool` | スクリーンショット・録画を OS レベルで抑止するか |

**表示要素**

| 要素 | クラス | 概要 |
|---|---|---|
| 上部バー | `PdfTopBar` | 戻るボタン・ページ番号・ブックマーク・メモ・TTS・分割モード |
| サイドドロワー | `PdfSideDrawer` | 目次・ブックマーク・メモ・キーワード検索の 4 タブ |
| PDFコンテンツ | `PdfDocumentViewBuilder` + `PageView` | 横スワイプでページ切り替え |
| インタラクション | `InteractiveViewer` | ピンチズーム（min 0.3x / max 5.0x）、ダブルタップ 2x ズーム |
| 検索ナビバー | `PdfSearchNavBar` | 検索ヒット数・前後移動ボタン（AppBar 直下） |
| 検索ハイライト | `PdfSearchHighlightOverlay` | ヒット箇所を黄色で塗りつぶし（フォーカス中は濃色） |
| TTS ハイライト | `PdfTtsHighlightOverlay` | ネイティブテキストパスで読み上げ中単語を水色ハイライト |
| OCR ハイライト | インライン `Positioned` | OCR パスで読み上げ中行を黄色ハイライト |
| テキスト選択 | `PdfPageTextOverlay` | ロングプレスで文字選択・コピー |
| リンク | `PdfLinkOverlay` | PDF リンクを透明ボタンで覆い外部URL/内部ページへ遷移 |
| サムネイルストリップ | `PdfThumbnailStrip` | 画面下部、現在ページを赤枠でハイライト、ブックマーク済みにしおりアイコン |
| ミニマップ | `PdfMiniMap` | ズーム 2.0x 超で右上に表示するナビゲーション小窓 |
| プレビュー | `_PagePreview` | フル品質レンダリング前に表示するローレゾサムネイル |

**主要なロジック**

**ドキュメント管理**
- `PdfDocumentCache.warmUp()` で Pdfium を事前オープン。`warmupComplete` フラグが true になるまでスピナーまたはキャッシュプレビューを表示
- `PdfDocumentRefDirect（autoDispose: false）` + キープアライブリスナーで pdfrx 1.3.5 の `didUpdateWidget` によるドキュメント解放バグを回避
- `PdfDocumentRefFile` は使用しない（二重 Pdfium オープンを防ぐため）

**ページング**
- `PageView` + `InteractiveViewer` の組み合わせ
- ズーム中（scale > 1.05）またはマルチタッチ中（pointer >= 2）は `NeverScrollableScrollPhysics` でスワイプを無効化
- 1.0x 未満へのズームアウト後に指を離すとスナップアニメーション（280ms, easeOut）で 1.0x に戻す
- 分割モード: `OverflowBox`（2倍幅）+ `ClipRect` で PDF の左右半分を交互に表示

**キーワード検索**
- `performPdfSearch()`（`search_controller.dart`）: 検索専用の `PdfDocument` を独立して開き、全ページのテキストを正規表現で走査
- ヒット結果は `SearchMatch（pageNumber, charStart, charEnd）` のリストで保持
- `PdfSearchHighlightOverlay` が `PdfTextRangeWithFragments` を通じて PDF 座標を画面座標に変換してハイライト描画

**TTS（音声読み上げ）**
- pdfrx の `loadText()` でネイティブテキストを取得。日本語文字が含まれない場合は OCR にフォールバック
- OCR: iOS = Apple Vision Framework（`app.tts.ocr` チャンネル）、Android = ML Kit（`TextRecognizer`）
- iOS 長文対策: テキストを 2000 文字チャンクに分割して逐次 `speak()`
- ハイライト: ネイティブテキストパスは `setProgressHandler` + フラグメントマッピングで文字インデックス → PDF 座標変換。OCR パスはバウンディングボックスを正規化座標でオーバーレイ配置

**キャプチャ保護**
- `preventCapture: true` の場合 `CaptureProtectionService.enable()` を呼び出し
- 画面を離れた際（dispose）に `disable()` で確実に解除

---

### 3.4 WebView 画面（WebViewPage）

**ルート**: `/webview`

**役割**  
アプリ内で外部 Web コンテンツを表示する。`flutter_inappwebview` を使用。

**プロパティ**

| プロパティ | 型 | 説明 |
|---|---|---|
| `url` | `String` | 表示するURL |
| `showBackToList` | `bool` | true のとき画面下部に「一覧へ戻る」固定バーを表示（Pick UP 記事用） |

**表示要素**

| 要素 | 内容 |
|---|---|
| AppBar | ページタイトル（取得前は URL を表示）、「ブラウザで開く」アイコン |
| ロードインジケーター | AppBar 下部に `LinearProgressIndicator`（ロード中のみ） |
| WebView | `InAppWebView`（JavaScript 有効、インラインメディア再生許可） |
| 「一覧へ戻る」バー | `showBackToList=true` の場合のみ表示。下スクロールで非表示、画面タップで再表示 |

**主要なロジック**

- http/https 以外のスキームへのリダイレクトは `shouldOverrideUrlLoading` でキャンセル（iOS WKWebView の無限ローディング防止）
- `showBackToList=true` 時は UserScript でタップイベントを監視し `flutter_inappwebview` の JS ハンドラ経由でバーを再表示
- iOS 初回 WebView 起動の遅延を `main.dart` の `_warmupWebView`（HeadlessInAppWebView）で事前軽減

---

## 4. データモデル

### 4.1 PdfContent

`contents.json` の各エントリーに対応するコンテンツデータモデル。

| フィールド | 型 | 説明 |
|---|---|---|
| `id` | `String` | コンテンツ一意ID（ファイル名生成に使用） |
| `title` | `String` | 表示タイトル |
| `description` | `String` | 概要説明文 |
| `category` | `String` | カテゴリー名（バッジ表示・フィルタリングに使用） |
| `url` | `String` | PDFダウンロードURL または WebコンテンツURL |
| `previewImageAsset` | `String` | プレビュー画像のアセットパス |
| `availableFrom` | `DateTime?` | 公開開始日時（null = 制限なし） |
| `availableTo` | `DateTime?` | 公開終了日時（null = 制限なし） |
| `preventCapture` | `bool` | スクリーンショット・録画抑止フラグ |
| `isWebContent` | `bool` | true の場合はダウンロードせず ChromeSafariBrowser で URL を開く |
| `lastUpdatedAt` | `DateTime?` | マスター管理の最終更新日時（null = バージョン管理なし） |

**主なメソッド**

| メソッド | 説明 |
|---|---|
| `availabilityStatusAt(DateTime now)` | `AvailabilityStatus`（available / notYet / expired）を返す |
| `isAvailableAt(DateTime now)` | 指定日時に閲覧可能かどうか |
| `PdfContent.fromJson(Map)` | JSON → インスタンス変換 |

**ユーティリティ関数**

| 関数 | 説明 |
|---|---|
| `buildSavePath(dir, content, langCode)` | ローカル保存パスを生成（`{id}_{langCode}_{タイトル}.pdf`形式） |
| `formatFileSize(bytes)` | バイト数を B/KB/MB の文字列に変換 |

### 4.2 ViewerArgs

PDFビューア遷移時に `go_router` の `extra` として渡す引数。

| フィールド | 型 | 説明 |
|---|---|---|
| `filePath` | `String?` | 開くローカルファイルのパス |
| `preventCapture` | `bool` | キャプチャ抑止フラグ（デフォルト: false） |

### 4.3 SearchMatch

キーワード検索のヒット情報を表す typedef record 型。

```dart
typedef SearchMatch = ({int pageNumber, int charStart, int charEnd});
```

| フィールド | 説明 |
|---|---|
| `pageNumber` | ヒットが存在するページ番号（1始まり） |
| `charStart` | ページ全文テキスト内のヒット開始文字インデックス |
| `charEnd` | ページ全文テキスト内のヒット終了文字インデックス（排他） |

---

## 5. サービス・リポジトリ設計

### 5.1 ContentMasterController

**クラス**: `ContentMasterNotifier`（`StateNotifier`）  
**プロバイダー**: `contentMasterProvider`

コンテンツ一覧の定義情報（`contents.json`）を取得・管理する。

**取得フローとフォールバック戦略**

```
起動時
  ① SharedPreferences キャッシュ を読み込み → 即時表示（ネットワーク待ち中でも表示）
  ② アプリ内サーバー（127.0.0.1:8765/contents.json）へ GET リクエスト
     ├─ 成功 → ContentMaster を更新、SharedPreferences に保存
     └─ 失敗 → assets バンドルの contents.json を直接読み込み
```

**時刻管理**  
サーバーの `Date` レスポンスヘッダーを「信頼できる時刻（trustedTime）」として使用。端末時計がずれていても公開期間の判定が正確に行われる。

**SharedPreferences キー**

| キー | 内容 |
|---|---|
| `content_master_json` | 最後に取得した contents.json の生文字列 |
| `content_master_fetched_at_ms` | 最終取得日時（ミリ秒） |
| `content_master_trusted_time_ms` | サーバーの Date ヘッダーから得た時刻（ミリ秒） |

### 5.2 StorageLimitService

PDF 保存容量の上限管理サービス（静的メソッドのみ）。

**SharedPreferences データスキーマ**

キー `storage_usage_json` に以下の JSON を保存:
```json
{
  "ファイル名.pdf": {
    "b": 1234567,
    "cid": "コンテンツID",
    "lat": 1700000000000
  }
}
```

| フィールド | 説明 |
|---|---|
| `b` | ファイルサイズ（バイト） |
| `cid` | コンテンツID（LRU削除・期限切れ判定に使用） |
| `lat` | 最終アクセス日時（ミリ秒、LRU順序の決定に使用） |

**上限管理**

- デフォルト上限: 500 MB（`storage_limit_bytes` に整数で保存）
- ユーザーは設定ダイアログから変更可能（100 / 300 / 500 / 1000 MB）

**LRU 自動削除フロー（`autoCleanup`）**

```
Step 1: availableTo が現在時刻より過去のファイルを期限切れとして削除
Step 2: まだ上限超過の場合、lat（最終アクセス時刻）昇順でファイルを削除
```

**主なメソッド**

| メソッド | 説明 |
|---|---|
| `checkBeforeDownload()` | ダウンロード前の容量チェック。超過なら `({usage, limit})` を返す |
| `recordFile(filename, bytes, contentId)` | DL完了後にファイル情報を記録 |
| `recordAccess(filename)` | PDFを開いたときに lat を更新 |
| `removeFile(filename)` | ファイル削除時に DB から除外 |
| `syncWithDirectory(dir)` | アプリ復帰時に実ファイルと DB の差分を補正 |
| `autoCleanup(...)` | 期限切れ・LRU 順で古いファイルを自動削除 |

### 5.3 ContentUpdateService

マスター JSON の `lastUpdatedAt` とローカル DL 日時を比較し、差分があるコンテンツをバックグラウンドで再ダウンロードするサービス。

**差し替えフロー**

```
checkAndUpdateAll() が呼ばれる（アプリ起動・復帰時）
  ↓ ローカルファイルが存在する各コンテンツについて
  ├─ lastUpdatedAt が未記録（旧バージョンからの移行）→ 再ダウンロード
  └─ lastUpdatedAt > 保存済みDL日時 → 再ダウンロード
       ↓ _redownloadSilently()
       ├─ 一時ファイル（.update_tmp）にダウンロード
       ├─ 旧ファイル削除 → 新ファイルに rename
       ├─ サムネイルキャッシュを無効化（最大20ページ分）
       └─ DLタイムスタンプを SharedPreferences に保存
```

**DL方式の切り替え**  
URL が `127.0.0.1` の場合はアプリ内サーバーから dio でダウンロード。サーバー未起動時は assets のバンドルにフォールバック。外部 URL は dio で直接ダウンロード。

**SharedPreferences キー**: `content_dl_at_{contentId}_{langCode}`（ISO 8601 形式）

### 5.4 NotificationService

ローカル Push 通知を管理する静的メソッドクラス（`flutter_local_notifications` を使用）。

**通知種別**

| 種別 | メソッド | 概要 |
|---|---|---|
| 即時通知 | `show()` | すぐに通知を表示 |
| スケジュール通知 | `schedule()` | 指定日時に通知を予約 |

**通知アクション**

- アクション ID: `action_download`
- iOS: `DarwinNotificationCategory`（カテゴリ ID `jal_content_download`）でダウンロードボタンを付与
- Android: `AndroidNotificationAction` でダウンロードボタンを付与

**スケジュール方式の違い**

| プラットフォーム | 方式 |
|---|---|
| iOS | `zonedSchedule`（UNCalendarNotificationTrigger）。アプリ kill 後も発火 |
| Android | ネイティブ `MethodChannel`（AlarmManager）。flutter_local_notifications の zonedSchedule はエンジン依存のため不使用 |

**主なコールバック**

- `onTap`: 通知本体タップ時 → `/backnumber` へ遷移
- `onAction`: アクションボタンタップ時 → 容量チェック後にバックグラウンドダウンロード開始

**タイムゾーン初期化**  
デバイスの IANA タイムゾーン識別子を `app.pdf.thumbnail` チャンネル経由で取得し `tz.local` に設定（UTC デフォルトによる時刻ずれを防止）。

### 5.5 PdfDocumentCache / PdfPreviewCache

**PdfDocumentCache**

Pdfium でのドキュメントオープン（数秒）を事前に行い、ビューア起動を高速化する。

| メソッド | 説明 |
|---|---|
| `warmUp(filePath)` | 非同期でドキュメントをオープンしてキャッシュ |
| `get(filePath)` | キャッシュ済み `PdfDocument` を返す（未キャッシュなら null） |
| `evict(filePath)` | キャッシュから除去してドキュメントを破棄 |

重複オープン防止のため `_pending` マップで進行中の Future を管理。

**PdfPreviewCache**

PDF の低解像度サムネイルをディスクにキャッシュする。

| メソッド | 説明 |
|---|---|
| `warmUp(pdfPath)` | ページ 0 のプレビューをバックグラウンドで生成・保存 |
| `preWarmStrip(pdfPath, pageCount)` | 全ページのストリップサムネイルを事前生成（iOS のみ有効） |
| `fetchNativeThumbnail(pdfPath, pageIndex)` | ネイティブ API（iOS: PDFKit / Android: PdfRenderer）でサムネイル取得 |

**キャッシュファイルパス**

| 種別 | パス形式 |
|---|---|
| プレビュー | `{pdfPath}.p{pageIndex}.jpg` |
| ストリップ | `{pdfPath}.strip{pageIndex}.jpg` |

取得優先度: ① ディスクキャッシュ → ② ネイティブサムネイル API → ③ pdfrx レンダリング

### 5.6 CaptureProtectionService

OS レベルのキャプチャ（スクリーンショット・録画）抑止を管理する。

| プラットフォーム | 実装方式 |
|---|---|
| Android | `jp.co.pdf.example.dev/capture_protection` MethodChannel 経由で `FLAG_SECURE` を設定 |
| iOS | `screen_protector` の UITextField トリック（スクリーンショット抑止）＋ バックグラウンド時の黒オーバーレイ（アプリスイッチャーでの内容漏洩防止） |

`PdfViewerPage` の `useEffect` で `preventCapture=true` の場合に `enable()`、`dispose` 時に `disable()` を確実に呼び出す。

### 5.7 AnalyticsService

Firebase Analytics へのイベント送信を一元管理する静的メソッドクラス。すべてのメソッドは fire-and-forget（await 不要）で設計されており、失敗しても UI に影響を与えない。

**イベント一覧**

| イベント名 | 説明 |
|---|---|
| `pdf_download_start` | PDFダウンロード開始 |
| `pdf_download_complete` | PDFダウンロード完了 |
| `pdf_download_failed` | PDFダウンロード失敗 |
| `pdf_download_cancelled` | PDFダウンロードキャンセル |
| `pdf_open` | PDFビューア起動 |
| `pdf_page_view` | PDFページ表示（ページ番号を含む） |
| `pdf_close` | PDFビューア終了（最終ページを含む） |
| `pdf_delete` | ダウンロード済みPDF削除 |
| `content_tab_switch` | コンテンツ一覧タブ切替（skyward / jal_shop / youtube） |
| `backnumber_page_view` | バックナンバー画面表示 |
| `backnumber_tab_switch` | バックナンバータブ切替（all / downloaded） |
| `web_content_open` | Web コンテンツを開いた |

パラメータ値は Firebase の 100 文字制限に合わせて `_trim()` で自動トリムする。

---

## 6. ウィジェット設計

### 6.1 PDF ビューア関連ウィジェット

| ウィジェット | 役割 | 主なプロパティ |
|---|---|---|
| `PdfTopBar` | PDF 上にオーバーレイ表示する上部カスタムバー。標準 AppBar は使わない。 | title, currentPage, pageCount, isBookmarked, hasMemo, ttsStatus, isSplitMode |
| `PdfSideDrawer` | 目次・ブックマーク・メモ・キーワード検索の 4 タブを持つサイドドロワー | outline, bookmarks, memos, filePath, 各コールバック |
| `PdfThumbnailStrip` | 画面下部の横スクロールサムネイルストリップ。現在ページを赤枠、ブックマーク済みページにしおりアイコンを表示。ダークモード時は色反転フィルターを適用。 | filePath, pageCount, currentPage, bookmarks, document |
| `PdfMiniMap` | ズーム倍率が 2.0x 超のとき右上に表示するナビゲーション小窓 | filePath, pageNumber, transformController, viewportSize |
| `PdfSearchNavBar` | 検索ヒット数・前後移動ボタンを表示するナビゲーションバー（AppBar 直下） | query, totalCount, currentIndex, currentPage |
| `PdfSearchHighlightOverlay` | 検索ヒット箇所を黄色でハイライト。フォーカスヒットは濃色。`PdfTextRangeWithFragments` を通じて PDF 座標を画面座標に変換 | page, pageSize, query, activeMatch |
| `PdfTtsHighlightOverlay` | TTS 読み上げ中の現在単語を水色でハイライト（ネイティブテキストパス） | page, pageSize, pageText, charStart, charEnd |
| `PdfLinkOverlay` | PDF のリンク領域を透明ボタンで覆い、外部 URL または内部ページリンクに対応 | page, pageSize, onUrlLink, onDestLink |

**`_PagePreview`（プライベート）**  
フル品質レンダリング完了前のプレースホルダー。ディスクキャッシュ → ネイティブサムネイル API → pdfrx レンダリングの順で表示し、キャッシュがない場合は生成してディスクに保存する。

### 6.2 コンテンツ一覧関連ウィジェット

| ウィジェット | 役割 |
|---|---|
| `ContentFeaturedCard` | 機内誌タブ用の大型フィーチャードカード。表紙画像を大きく表示し、タイトル・説明・ダウンロード/開くアクションボタンを配置 |
| `ContentPreviewCard` | サムネイルを中心とした 2 列グリッド用カード。ダウンロード済みはサムネイル表示、未ダウンロードはプレースホルダー、ダウンロード中は進捗オーバーレイを表示 |
| `ContentListCard` | テキスト情報中心のリスト表示用カード。カテゴリーバッジ・説明文・ダウンロード進捗・削除ボタン等の詳細情報を表示 |
| `ShopTab` | JAL SHOP タブ。機内販売商品（画像・タイトル・価格・評価）のグリッドリスト。タップで WebView へ遷移 |
| `YoutubeTab` | Youtube【公式】タブ。動画サムネイル（YouTubeThumbnail API）とタイトルのリスト。タップで YouTube WebView へ遷移 |

### 6.3 共通ウィジェット

**`StorageLimitDialog`** 関連関数（`storage_limit_dialog.dart`）

| 関数 | 説明 |
|---|---|
| `showStorageLimitExceededDialog()` | 容量上限超過時の警告ダイアログ（使用量バー付き） |
| `showStorageSettingsDialog()` | ストレージ上限設定ダイアログ（現在の使用状況と上限変更） |

---

## 7. モックサーバー設計

**クラス**: `PdfAssetServer`（`mock_server` パッケージ）  
**エンドポイント**: `http://127.0.0.1:8765/`（IPv4 直接指定。iOS は localhost が IPv6 に解決される問題を回避）

**起動方式**  
`main()` で `_startPdfServer()` を呼び出す。Flutter の `shelf` + `shelf_io` を使って同一プロセスで HTTP サーバーを起動する。ホットリスタートでの二重バインドを防ぐため `shared: true` オプションを使用。ポートビジー時は 500ms 間隔で最大 3 回リトライ。

**PDF の遅延ロード（Lazy Loading）方式**

起動時に PDF を一括でメモリに展開しない。

```
起動時
  contents.json のみインメモリに保持（_memCache）

最初のリクエスト時（例: /skyward_2026_07.pdf）
  assets/pdfs/{filename} を システム一時ディレクトリへ展開
  展開完了後、_fileCache に File オブジェクトを登録
  2回目以降のリクエストは _fileCache から直接配信
```

重複展開を防ぐために `_extracting` マップで進行中の Future を管理する（`putIfAbsent` で同一 Future を共有）。

**warmUp**  
起動後すぐに `_pdfServer.warmUp(filenames)` を fire-and-forget で呼び出し、ユーザーが PDF を開く前に展開を完了させる。

**Range Request 対応**  
インメモリ（contents.json）とファイル（PDF）の両方で `Range: bytes=start-end` ヘッダーを解析して部分レスポンス（206）を返す。pdfrx がページ単位での範囲取得を行うため必須。

**エンドポイント一覧**

| URL | 内容 | 配信方式 |
|---|---|---|
| `/contents.json` | コンテンツ定義マスター | インメモリ（起動時にロード済み） |
| `/{filename}.pdf` | PDF ファイル | ディスク（遅延展開後にストリーム配信） |

---

## 8. 多言語・テーマ設計

### 多言語対応

| 項目 | 内容 |
|---|---|
| 対応言語 | 日本語（ja）/ 英語（en） |
| 管理クラス | `AppL10n`（`core/utils/l10n.dart`） |
| 切替方法 | AppBar 右上の言語アイコンから選択ダイアログで切替 |
| 永続化 | `SharedPreferences`（キー: `app_locale`） |
| 初期化優先順位 | ① 保存済み設定 → ② 端末システム言語 → ③ 日本語（フォールバック） |

`AppL10n.of(context)` でウィジェットツリーのどこからでも文字列を参照可能。`MaterialApp.router` の `localizationsDelegates` に `AppL10n.delegate`・`GlobalMaterialLocalizations.delegate`・`GlobalWidgetsLocalizations.delegate`・`GlobalCupertinoLocalizations.delegate` を登録。

### テーマ設計

| 項目 | 内容 |
|---|---|
| テーマモード | system / light / dark の 3 択 |
| 切替方法 | AppBar 右上のアイコンから選択ダイアログで切替 |
| 永続化 | `SharedPreferences`（キー: `theme_mode`） |
| ブランドカラー | 赤 `#CC0000`（AppBar・ElevatedButton・FAB・TabBar インジケーター） |

**テーマ設定（`_buildTheme()`）**

| 要素 | ライトモード | ダークモード |
|---|---|---|
| AppBar 背景 | 白 | `#1E1E1E` |
| ElevatedButton | 赤背景・白文字 | 赤背景・白文字 |
| FAB | 赤背景・白アイコン | 赤背景・白アイコン |
| CircularProgressIndicator | 赤 | 赤 |

---

## 9. 依存パッケージ一覧

### 状態管理

| パッケージ | バージョン | 用途 |
|---|---|---|
| `hooks_riverpod` | ^2.6.1 | Riverpod + Flutter Hooks の統合パッケージ |
| `flutter_hooks` | ^0.20.5 | useState / useEffect 等のフック |
| `riverpod_annotation` | ^2.6.1 | Riverpod コード生成アノテーション |
| `freezed_annotation` | ^3.1.0 | イミュータブルクラス生成 |

### ナビゲーション

| パッケージ | バージョン | 用途 |
|---|---|---|
| `go_router` | ^14.6.1 | 宣言的ルーティング |

### PDF ビューア

| パッケージ | バージョン | 用途 |
|---|---|---|
| `pdfrx` | ^1.0.0 | Pdfium ベースの PDF レンダリング・テキスト抽出 |

### ファイル・ストレージ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `path_provider` | ^2.1.5 | アプリドキュメントディレクトリなどのパス取得 |
| `file_picker` | ^8.0.0 | 端末ストレージからのファイル選択 |
| `shared_preferences` | ^2.5.5 | 設定値・キャッシュ情報の永続化 |

### ネットワーク・ダウンロード

| パッケージ | バージョン | 用途 |
|---|---|---|
| `dio` | ^5.7.0 | HTTP クライアント（コンテンツマスター取得・PDF DL） |
| `background_downloader` | ^9.0.0 | バックグラウンドでの大容量 PDF ダウンロード |
| `screen_protector` | ^1.5.2 | iOS キャプチャ抑止 |

### 通知

| パッケージ | バージョン | 用途 |
|---|---|---|
| `flutter_local_notifications` | >=16.3.0 <17.0.0 | ローカル Push 通知（即時・スケジュール） |
| `timezone` | ^0.9.4 | スケジュール通知の IANA タイムゾーン処理 |

### Firebase

| パッケージ | バージョン | 用途 |
|---|---|---|
| `firebase_core` | ^2.27.0 | Firebase 初期化 |
| `firebase_analytics` | ^10.10.0 | ユーザー行動ログ分析 |

### WebView

| パッケージ | バージョン | 用途 |
|---|---|---|
| `flutter_inappwebview` | ^6.1.5 | インアプリ WebView（iOS: WKWebView / Android: WebView） |

### テキスト認識・読み上げ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `google_mlkit_text_recognition` | ^0.13.0 | Android での OCR（ML Kit） |
| `flutter_tts` | ^4.2.0 | テキスト読み上げ（iOS: AVSpeechSynthesizer / Android: TTS） |

### モックサーバー

| パッケージ | バージョン | 用途 |
|---|---|---|
| `mock_server` | path: ./mock_server | アプリ内 HTTP サーバー（開発用コンテンツ配信） |

### 開発ツール（dev_dependencies）

| パッケージ | バージョン | 用途 |
|---|---|---|
| `build_runner` | ^2.4.15 | コード生成実行 |
| `freezed` | ^3.0.6 | Freezed クラス生成 |
| `riverpod_generator` | ^2.6.5 | Riverpod プロバイダー生成 |
| `flutter_launcher_icons` | ^0.14.3 | アプリアイコン生成 |
| `flutter_lints` | ^3.0.0 | Lint ルール |
