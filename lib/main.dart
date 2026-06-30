import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    GoRoute(
      path: '/',
      builder: (context, state) => const ContentListPage(),
    ),
    GoRoute(
      path: '/viewer',
      pageBuilder: (context, state) {
        // state.extra でコンテンツ一覧から渡されたローカルファイルパスを受け取る
        // 端末からファイルを直接開く場合は null になる
        final filePath = state.extra as String?;
        return NoTransitionPage(
          child: PdfViewerPage(initialFilePath: filePath),
        );
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

void main() {
  // Flutter エンジンの初期化（SharedPreferences など非同期処理の前に必要）
  WidgetsFlutterBinding.ensureInitialized();

  // 16ms を超えたフレームをログ出力（ページ送り・ズームなどの応答速度計測用）
  WidgetsBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      final ms = t.totalSpan.inMilliseconds;
      if (ms > 16) {
        debugPrint('[Frame] ${ms}ms (build:${t.buildDuration.inMilliseconds}ms raster:${t.rasterDuration.inMilliseconds}ms)');
      }
    }
  });

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
          color: scheme.brightness == Brightness.dark
              ? Colors.white
              : Colors.black,
        ),
        actionsIconTheme: IconThemeData(
          color: scheme.brightness == Brightness.dark
              ? Colors.white
              : Colors.black,
        ),
        titleTextStyle: TextStyle(
          color: scheme.brightness == Brightness.dark
              ? Colors.white
              : Colors.black,
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
        labelColor: scheme.brightness == Brightness.dark ? Colors.white : Colors.black,
        unselectedLabelColor: scheme.brightness == Brightness.dark ? Colors.white60 : Colors.black54,
        indicatorColor: scheme.brightness == Brightness.dark ? Colors.white : Colors.black,
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
      theme: _buildTheme(ColorScheme.fromSeed(
        seedColor: const Color(0xFFCC0000),
        primary: const Color(0xFFCC0000),
        onPrimary: Colors.white,
      )),
      // ダークモード用テーマ（brightness: dark の ColorScheme を使用）
      darkTheme: _buildTheme(ColorScheme.fromSeed(
        seedColor: const Color(0xFFCC0000),
        brightness: Brightness.dark,
      )),
      // 画面遷移の設定（上記 _router を使用）
      routerConfig: _router,
    );
  }
}
