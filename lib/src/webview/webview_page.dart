import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../l10n.dart';

/// PDF内のリンクをタップしたときにアプリ内で開くWebView画面。
/// flutter_inappwebview を使用して実装。
/// [url] には開くWebページのURL文字列を渡す。
class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key, required this.url});

  /// 表示するWebページのURL
  final String url;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  /// InAppWebViewの操作コントローラー（ページ遷移・JS実行・タイトル取得など）
  InAppWebViewController? _controller;

  /// ページ読み込み中かどうかのフラグ（AppBar下部プログレスバー表示に使用）
  bool _isLoading = true;

  /// ページタイトル（onLoadStop で取得後に AppBar に表示）
  String _title = '';

  /// 読み込み進捗（0.0〜1.0）。indeterminate なら null として扱う。
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _title.isEmpty ? widget.url : _title,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: AppL10n.of(context).openInBrowser,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '${AppL10n.of(context).urlCopied}${widget.url}'),
                ),
              );
            },
          ),
        ],
        // ページ読み込み中のみ AppBar 下部に進捗バーを表示
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  // 進捗が 0 のうちは indeterminate 表示
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: const Color(0xFFAA0000),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : null,
      ),
      body: InAppWebView(
        // 初期読み込みURLを URLRequest で指定
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          // JavaScript を有効化
          javaScriptEnabled: true,
          // URL ナビゲーションをコールバックで制御可能にする
          useShouldOverrideUrlLoading: true,
          // インライン動画再生を許可
          allowsInlineMediaPlayback: true,
          // 動画の自動再生をユーザー操作なしで許可
          mediaPlaybackRequiresUserGesture: false,
          // HTTP（平文通信）を許可
          clearCache: false,
        ),
        // WebView が生成されたタイミングでコントローラーを保持
        onWebViewCreated: (controller) {
          _controller = controller;
        },
        // ページ読み込み開始
        onLoadStart: (controller, url) {
          if (mounted) setState(() => _isLoading = true);
        },
        // 読み込み進捗の更新（0〜100 の int → 0.0〜1.0 に変換）
        onProgressChanged: (controller, progress) {
          if (mounted) setState(() => _progress = progress / 100.0);
        },
        // ページ読み込み完了：タイトルを取得して AppBar に反映
        onLoadStop: (controller, url) async {
          final title = await controller.getTitle();
          if (mounted) {
            setState(() {
              _isLoading = false;
              _title = title ?? widget.url;
            });
          }
        },
        // ネットワークエラー時はローディングを解除
        onReceivedError: (controller, request, error) {
          if (mounted) setState(() => _isLoading = false);
        },
      ),
    );
  }
}
