import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/utils/l10n.dart';

/// PDF内のリンクをタップしたときにアプリ内で開くWebView画面。
/// flutter_inappwebview を使用して実装。
/// [url] には開くWebページのURL文字列を渡す。
class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    required this.url,
    this.showBackToList = false,
  });

  /// 表示するWebページのURL
  final String url;

  /// true のとき画面下部に「一覧へ戻る」固定バーを表示する（PickUP記事用）
  final bool showBackToList;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
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
      bottomNavigationBar: widget.showBackToList
          ? SafeArea(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 296),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFCC0000),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
                            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('一覧へ戻る'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: InAppWebView(
        // 初期読み込みURLを URLRequest で指定
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          // JavaScript を有効化
          javaScriptEnabled: true,
          // インライン動画再生を許可
          allowsInlineMediaPlayback: true,
          // 動画の自動再生をユーザー操作なしで許可
          mediaPlaybackRequiresUserGesture: false,
          clearCache: false,
        ),
        onWebViewCreated: (_) {},
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
