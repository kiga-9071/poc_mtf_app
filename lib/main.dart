import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mock_server/pdf_asset_server.dart';

import 'src/controllers/locale_controller.dart';
import 'src/controllers/theme_controller.dart';
import 'src/l10n.dart';
import 'src/pages/content_list/content_list_page.dart';
import 'src/pages/pdf_viewer/pdf_viewer_page.dart';
import 'src/webview/webview_page.dart';

// ── ルーティング定義 ──────────────────────────────────────────────────────────

/// go_router によるアプリ内画面遷移の設定。
/// - `/`        : コンテンツ一覧画面（起動時の初期画面）
/// - `/viewer`  : PDFビューアー画面（extra にファイルパスを渡す）
/// - `/webview` : インアプリWebView画面（extra にURLを渡す）
final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ContentListPage()),
    GoRoute(
      path: '/viewer',
      builder: (context, state) {
        // state.extra でコンテンツ一覧から渡されたローカルファイルパスを受け取る
        // 端末からファイルを直接開く場合は null になる
        final filePath = state.extra as String?;
        return PdfViewerPage(initialFilePath: filePath);
      },
    ),
    GoRoute(
      path: '/webview',
      builder: (context, state) {
        // state.extra でPDFリンクタップ時に渡されたURLを受け取る
        final url = state.extra as String;
        return WebViewPage(url: url);
      },
    ),
  ],
);

// ── エントリーポイント ─────────────────────────────────────────────────────────

/// アプリ内 PDF サーバーのシングルトン。ホットリスタートでの二重バインドを防ぐためトップレベルで保持する。
final _pdfServer = PdfAssetServer();

/// [url] の末尾パスセグメントをファイル名として返す。[Uri.parse] 失敗時は `/` 分割でフォールバック。
String _filenameFromUrl(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
  } catch (_) {
    // URL として解釈できない場合は末尾セグメントをフォールバック利用する。
  }
  return url.split('/').last;
}

/// `contents.json` を唯一の真実源として配信対象 PDF を特定し、[_pdfServer] を起動する。
///
/// assets のロードに失敗してもアプリ起動は継続する（サーバーモードでのダウンロードのみ失敗）。
Future<void> _startPdfServer() async {
  try {
    final raw = await rootBundle.loadString(
      'packages/mock_server/assets/contents.json',
    );
    final data = jsonDecode(raw) as Map<String, dynamic>;

    final filenames = <String>{};
    for (final value in data.values) {
      final items = value as List<dynamic>;
      for (final item in items) {
        final url = (item as Map<String, dynamic>)['url'] as String;
        filenames.add(_filenameFromUrl(url));
      }
    }

    final cache = <String, Uint8List>{};
    for (final filename in filenames) {
      final asset = await rootBundle.load(
        'packages/mock_server/assets/pdfs/$filename',
      );
      cache[filename] = asset.buffer.asUint8List();
    }

    await _pdfServer.start(cache);
  } catch (e, st) {
    debugPrint('PDF server start failed: $e\n$st');
  }
}

Future<void> main() async {
  // Flutter エンジンの初期化（SharedPreferences など非同期処理の前に必要）
  WidgetsFlutterBinding.ensureInitialized();
  await _startPdfServer();
  // ProviderScope: Riverpod の状態管理をアプリ全体に提供するルートウィジェット
  runApp(const ProviderScope(child: MyApp()));
}

// ── テーマ定義 ────────────────────────────────────────────────────────────────

/// ライト／ダーク共通のテーマ設定を生成する関数。
/// AppBar や ボタン・FAB などのカラーは赤 (#CC0000) をブランドカラーとして統一。
/// [scheme] に渡す ColorScheme の brightness によってライト／ダークが切り替わる。
ThemeData _buildTheme(ColorScheme scheme) => ThemeData(
  colorScheme: scheme,
  useMaterial3: true,
  appBarTheme: AppBarTheme(
    // ライト: 白背景・黒文字 / ダーク: 濃いグレー背景・白文字
    backgroundColor: scheme.brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Colors.white,
    foregroundColor: scheme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black,
    iconTheme: IconThemeData(
      color: scheme.brightness == Brightness.dark ? Colors.white : Colors.black,
    ),
    actionsIconTheme: IconThemeData(
      color: scheme.brightness == Brightness.dark ? Colors.white : Colors.black,
    ),
    titleTextStyle: TextStyle(
      color: scheme.brightness == Brightness.dark ? Colors.white : Colors.black,
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
    elevation: 0,
    // スクロール時に影を出して AppBar とコンテンツを区別する
    scrolledUnderElevation: 1,
    surfaceTintColor: Colors.transparent,
  ),
  // ElevatedButton: 赤背景・白文字で統一
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFCC0000),
      foregroundColor: Colors.white,
    ),
  ),
  // FAB（フローティングアクションボタン）: 赤背景・白アイコン
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: Color(0xFFCC0000),
    foregroundColor: Colors.white,
  ),
  // CircularProgressIndicator のカラー
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: Color(0xFFCC0000),
  ),
  // TabBar（ドロワー内の目次／ブックマーク／検索タブ）のカラー
  tabBarTheme: TabBarThemeData(
    labelColor: scheme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black,
    unselectedLabelColor: scheme.brightness == Brightness.dark
        ? Colors.white60
        : Colors.black54,
    indicatorColor: scheme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black,
  ),
);

// ── ルートウィジェット ─────────────────────────────────────────────────────────

/// アプリのルートウィジェット。
/// Riverpod の ConsumerWidget として locale と themeMode を監視し、
/// どちらかが変わると MaterialApp.router が再ビルドされて UI 全体に反映される。
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 現在の表示言語（localeProvider で管理）
    final locale = ref.watch(localeProvider);
    // 現在のテーマモード: system / light / dark（themeModeProvider で管理）
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'PDF Viewer',
      // 表示言語の設定
      locale: locale,
      // サポートする言語一覧（locale_provider.dart で定義）
      supportedLocales: supportedLocales,
      // 多言語対応デリゲートの登録
      // AppL10n.delegate: アプリ独自の文字列
      // Global系: Material・Cupertino ウィジェットの標準文字列
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // テーマモードの設定（system の場合は端末設定に自動追従）
      themeMode: themeMode,
      // ライトモード用テーマ（brightness: light の ColorScheme を使用）
      theme: _buildTheme(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFFCC0000),
          primary: const Color(0xFFCC0000),
          onPrimary: Colors.white,
        ),
      ),
      // ダークモード用テーマ（brightness: dark の ColorScheme を使用）
      darkTheme: _buildTheme(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFFCC0000),
          brightness: Brightness.dark,
        ),
      ),
      // 画面遷移の設定（上記 _router を使用）
      routerConfig: _router,
    );
  }
}
