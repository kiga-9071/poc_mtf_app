# 実装計画: 開発用 PDF サーバーのアプリ内起動化（shelf）

## Context

検証用 PoC アプリをクライアントに配布し、実機で操作してもらうことが目的。
現行の `start_server.py`（外部 Python サーバー、port 8765）は、クライアント側で Python サーバーを
起動し `adb reverse` する必要があり、配布には非現実的である。

そこで PDF 配信を **アプリ内サーバー方式** に置き換える。`shelf` を使い、Flutter アプリと
同一プロセスで loopback（`127.0.0.1:8765`）に HTTP サーバーを立て、`mock_server/assets/pdfs/` に
同梱した PDF を配信する。クライアントはアプリをインストールするだけで、外部プロセス・
`adb reverse`・ネットワーク接続なしに、ダウンロードの UX（進捗バー・キャンセル）を含めて確認できる。

主要な決定事項:

- **配信方式はアプリ内サーバー（shelf）**。`mock_web_server` は dispatcher が関数型で
  `MockResponse.body` が文字列のみ（バイナリ配信が用途外）のため不採用。`shelf` は `Response.ok`
  の body が `List<int>`（`Uint8List`）をバイナリ送信し、loopback バインドできる。
  - 出典: pub.dev `mock_web_server` ドキュメント、context7 `/dart-lang/shelf`。
- **assets 一式（`pdfs/`・`contents.json`・`previews/`）を `mock_server/assets/` に集約**し、
  `mock_server` を Flutter パッケージ化。アプリは `packages/mock_server/...` で参照する。
  - 参照形式 `packages/<pkg>/<asset>` は Flutter 公式で確認済み（出典: docs.flutter.dev assets-and-images）。
- **PDF はビルド時にアプリへバンドルされる**（同一プロセスのアプリ内サーバーが配信するため不可避）。
  許容する。配信する PDF は公開可能なサンプルで機微情報を含まない前提。
- **リリースビルドでもサーバーを起動する**（クライアント配布の検証アプリのため）。本番移行時は
  末尾の「本番移行チェックリスト」に従いアプリ内サーバーを外し、リモート URL に差し替える。
- **ADR は起票しない**（PoC の開発専用ツールとして不要と判断）。

## ディレクトリ構成（変更後）

```
poc_mtf_app/
├── lib/
│   ├── main.dart                       # ★ main() を async 化・サーバー起動を追加
│   ├── src/entities/pdf_content.dart   # ★ assetPath / previewImageAsset を packages/ 参照に
│   └── src/pages/content_list/
│       └── content_list_page.dart      # ★ contents.json を packages/ 参照に
├── mock_server/                        # ★ 新規: Flutter パッケージ
│   ├── pubspec.yaml                    #   shelf 依存 + flutter_lints + assets 宣言
│   ├── analysis_options.yaml           #   flutter_lints を include
│   ├── lib/
│   │   └── pdf_asset_server.dart       #   PdfAssetServer（shelf, クラス自体は Flutter 非依存）
│   └── assets/                         # ★ アプリ assets/ から移動
│       ├── contents.json               #   URL を 127.0.0.1 に変更
│       ├── pdfs/                       #   配信する PDF 群（9 ファイル / 約 6MB）
│       └── previews/                   #   プレビュー画像
├── pubspec.yaml                        # ★ assets 宣言を削除し mock_server を path 依存に
├── docs/screen_definition.html         # ★ adb reverse / localhost の記述を更新
├── README.md                           # ★ サーバー起動・adb reverse 節を更新
└── start_server.py / generate_pdfs.py  # ★ 動作確認後に削除（pdf_server/ も）
```

## 確認済みの技術前提

- `shelf` の `Response.ok(body, {headers})` は `List<int>` / `Uint8List` をバイナリ送信。
  `serve(Handler, InternetAddress.loopbackIPv4, 8765, shared: true)` で loopback バインド。
  同一プロセスの Dio が接続するため原理的にアプリ内完結（出典: context7 `/dart-lang/shelf`）。
- Flutter のパッケージアセット参照は `packages/<pkg>/<asset>`（出典: docs.flutter.dev）。
- **配信対象は `contents.json` から導出する**（`AssetManifest.listAssets()` のパッケージアセット
  列挙形式が公式ドキュメントで未確証のため、依存を避ける）。`contents.json` の各 URL を
  `split('/').last` でファイル名化し、これを単一の真実源とする。
- **URL は `127.0.0.1` 固定**（`localhost` は環境により IPv6 `::1` を返し、`loopbackIPv4` バインドと
  食い違って接続失敗する恐れがあるため）。

`[要検証]`（実装時に確認）:
- `Request.url.path` のパーセントデコード挙動、および Dio→shelf 往復でのファイル名一致。
- 日本語ファイル名（`SKYWARD 2026年5月号.pdf`）の NFC/NFD 正規化差（macOS FS は NFD 傾向）。
  キャッシュキー（`contents.json` の `split('/').last`）・`rootBundle.load` パス・`request.url.path`
  の3者が同一文字列になる必要がある。
- iOS 実機・Android Emulator での `127.0.0.1:8765` 到達性。

## 変更・新規ファイル一覧

### 1. assets 移動

`assets/contents.json`・`assets/pdfs/`・`assets/previews/` を `mock_server/assets/` 配下へ
`git mv` で移動。アプリ直下の `assets/` は削除する。

### 2. 新規: `mock_server/pubspec.yaml`（Flutter パッケージ）

```yaml
name: mock_server
description: In-app PDF dev server (shelf) replacing start_server.py
version: 1.0.0

environment:
  sdk: '>=3.12.0 <4.0.0'
  flutter: '>=3.44.0'

dependencies:
  flutter:
    sdk: flutter
  shelf: ^1.4.0

dev_dependencies:
  flutter_lints: ^3.0.0

flutter:
  assets:
    - assets/
    - assets/pdfs/
    - assets/previews/
```

`mock_server/analysis_options.yaml` は `include: package:flutter_lints/flutter.yaml`。

### 3. 新規: `mock_server/lib/pdf_asset_server.dart`

クラス自体は shelf + `dart:io` のみで Flutter を import しない（PDF バイト列は注入）。
パッケージは assets 宣言のため Flutter パッケージだが、クラスは疎結合でテスト容易。

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

class PdfAssetServer {
  static const int port = 8765;
  HttpServer? _server;

  /// pdfCache: ファイル名（例: 'dx_guide_jp.pdf'）→ PDF バイト列
  Future<void> start(Map<String, Uint8List> pdfCache) async {
    if (_server != null) return; // 多重起動防止
    try {
      _server = await io.serve(
        _handler(pdfCache),
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
    } on SocketException catch (e) {
      // 配布アプリでは外部プロセスは想定しないが、競合時はダウンロードが失敗する
      stderr.writeln('PdfAssetServer: port $port bind failed: $e');
    }
  }

  Handler _handler(Map<String, Uint8List> cache) => (Request request) {
    final filename = request.url.path; // 先頭スラッシュ無し・デコード済み
    final bytes = cache[filename];
    if (bytes == null) return Response.notFound('Not found: $filename');
    return Response.ok(bytes, headers: {
      HttpHeaders.contentTypeHeader: 'application/pdf',
      HttpHeaders.contentLengthHeader: '${bytes.length}',
    });
  };

  Future<void> shutdown() async {
    await _server?.close(force: true);
    _server = null;
  }
}
```

進捗バー UX の確認用に、loopback 配信が速すぎて進捗が一瞬で終わる場合は、`_handler` を
`Stream`＋`Future.delayed` のチャンク送出に変える遅延注入を検討する（後述 検証 §3、`[要確認]`）。

### 4. `pubspec.yaml`（アプリ）

`flutter: assets:` セクションを削除し、`mock_server` を path 依存として追加する。

```yaml
dependencies:
  # ... 既存はそのまま ...
  mock_server:
    path: ./mock_server

flutter:
  uses-material-design: true
  # assets セクションは削除（PDF・画像は mock_server がバンドル）
```

### 5. `mock_server/assets/contents.json`

全エントリの URL を `http://localhost:8765/...` から `http://127.0.0.1:8765/...` に変更する
（IPv4/IPv6 不一致の回避）。内容のその他は変更なし。

### 6. `lib/main.dart` — サーバー自動起動（シングルトン）

`PdfAssetServer` をトップレベルのシングルトンとして保持し、ホットリスタートでの leak を防ぐ。
配信対象は `contents.json` から導出する。リリースビルドでも起動する（`kDebugMode` ガードなし）。

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mock_server/pdf_asset_server.dart';

final _pdfServer = PdfAssetServer(); // トップレベル・シングルトン

Future<void> _startPdfServer() async {
  try {
    final raw =
        await rootBundle.loadString('packages/mock_server/assets/contents.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final filenames = <String>{};
    for (final list in data.values) {
      for (final item in list as List) {
        filenames.add(((item as Map)['url'] as String).split('/').last);
      }
    }
    final cache = <String, Uint8List>{};
    for (final name in filenames) {
      final bytes =
          await rootBundle.load('packages/mock_server/assets/pdfs/$name');
      cache[name] = bytes.buffer.asUint8List();
    }
    await _pdfServer.start(cache);
  } catch (e, st) {
    debugPrint('PDF server start failed: $e\n$st'); // 失敗してもアプリは起動継続
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _startPdfServer();
  runApp(const ProviderScope(child: MyApp()));
}
```

全 PDF（約 6MB）をメモリ常駐させる。大容量化したら都度 `rootBundle.load` に切り替える。

### 7. `lib/src/entities/pdf_content.dart`

`assetPath` getter（現 `:33`）と `previewImageAsset` デフォルト（現 `:47`）に
`packages/mock_server/` プレフィックスを付ける。

```dart
String get assetPath =>
    'packages/mock_server/assets/pdfs/${url.split('/').last}';
// ...
previewImageAsset: json['previewImage'] as String? ??
    'packages/mock_server/assets/previews/${json['id']}.png',
```

### 8. `lib/src/pages/content_list/content_list_page.dart`

`contents.json` のロードパス（現 `:174`）を変更する。

```dart
final raw = await rootBundle.loadString('packages/mock_server/assets/contents.json');
```

### 9. 変更不要（参照の間接化で吸収）

- `content_list_card.dart:76` / `content_preview_card.dart:82` の `rootBundle.load(content.assetPath)`
  → `assetPath` getter 変更で吸収。
- `content_preview_card.dart:191` の `Image.asset(content.previewImageAsset)` → 同上。
- Dio ダウンロード処理（`content.url` 使用）・`source_mode_controller.dart`。
- コード生成: `lib/` に `@freezed`/`@riverpod` アノテーション・生成物は存在しないため build_runner 実行不要。

### 10. `docs/screen_definition.html` / `README.md`

`adb reverse` / `localhost:8765` / 「サーバーモード=サーバー起動必要」の旧記述を、
アプリ内サーバー方式（外部起動不要）に更新する。

### 11. 削除（動作確認後）

`start_server.py` / `generate_pdfs.py` / 生成物 `pdf_server/`。`.gitignore` の該当エントリも整理。

## 実装前に確認すべき前提

動作確認は iOS・Android の実機/シミュレータでのみ行う（macOS デスクトップは対象外のため
macOS entitlements は不問）。

- **iOS ATS**: `ios/Runner/Info.plist` に ATS キーなし。`127.0.0.1` への HTTP 接続可否を
  実機/Simulator で確認。`[要確認]`
- **Android cleartext**: `AndroidManifest.xml` に `usesCleartextTraffic="true"` 設定済み（確認済み）。

## エラーハンドリング方針

- ポート競合（`SocketException`）: `start()` 内で `stderr` にログし握り潰す。配布アプリでは外部
  プロセスを想定しないが、他アプリが 8765 を占有していると静かにダウンロードが失敗する点に注意。
- ホットリスタート時の二重バインド: トップレベル・シングルトン + `_server != null` 判定 + `shared: true`。
- assets ロード失敗: `_startPdfServer()` 全体を `try/catch` し、アプリ起動は継続。

## 実装順序

1. `assets/` を `mock_server/assets/` へ移動（`git mv`）
2. `mock_server/pubspec.yaml`（Flutter パッケージ）と `analysis_options.yaml` を作成
3. `mock_server/lib/pdf_asset_server.dart` を実装
4. アプリ `pubspec.yaml` の assets 宣言削除・`mock_server` path 依存追加 → `flutter pub get`（生成不要）
5. `contents.json` の URL を `127.0.0.1` に変更
6. `pdf_content.dart`・`content_list_page.dart` を `packages/mock_server/` 参照に変更
7. `lib/main.dart` をシングルトン・async 化し `_startPdfServer()` を追加
8. iOS `Info.plist` を確認（必要なら追加）。Android は設定済み
9. iOS・Android の実機/シミュレータで `flutter run`、アプリのサーバーモードでダウンロードして疎通確認
10. `SourceMode.server` / `local` のダウンロード、進捗バー・キャンセル・404 を確認
11. 機内誌（日本語ファイル名）で NFC/NFD 一致、iOS 実機/Emulator で IPv4 到達性を確認
12. `flutter analyze`（既存テストがあれば `flutter test`）
13. `start_server.py` / `generate_pdfs.py` / `pdf_server/` を削除し `screen_definition.html`・`README.md` を更新

## 検証方法

1. 旧 `start_server.py` を停止した状態で iOS・Android の実機/シミュレータで `flutter run`
2. ソースモードを「サーバー」に設定
3. 機内誌 PDF（約 5.9MB）をダウンロード → 進捗バーが段階表示されるか確認。
   loopback で一瞬に終わり観測できない場合は `_handler` に遅延注入を追加（`[要確認]`）
4. ダウンロード完了後に PDF ビューアで開ける
5. キャンセルボタンが機能する
6. 存在しないパスへのアクセスで 404 が返る
7. `local` モードでもダウンロード（assets コピー）が動作する
8. グリッド表示でプレビュー画像が表示される（previews/ の packages 参照）
9. ホットリスタート後もクラッシュ・leak せず再ダウンロードできる
10. iOS 実機/Simulator・Android Emulator で 3〜5 と `127.0.0.1` 到達性が再現する
11. `flutter run --release` でもサーバーが起動しダウンロードできる（配布形態の確認）

## 本番移行チェックリスト（将来）

- `pubspec.yaml` の `mock_server` path 依存を削除
- `lib/main.dart` の `_startPdfServer()` 呼び出しとシングルトンを削除
- `contents.json` の URL を本番リモート URL に差し替え
- `mock_server/` パッケージと assets バンドルを除去

## 未解決事項

- `Request.url.path` のデコード挙動・日本語ファイル名の NFC/NFD 一致は実装時に機内誌で実検証。
- `127.0.0.1:8765` の iOS・Android 実機/シミュレータ到達性は実装時に確認。
- 既存テストは現状なし。`flutter test` の回帰確認範囲はテスト追加状況に依存する。
