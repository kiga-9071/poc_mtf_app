import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/utils/l10n.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    required this.url,
    this.showBackToList = false,
  });

  final String url;

  /// true のとき画面下部に「一覧へ戻る」固定バーを表示する（PickUP記事用）
  final bool showBackToList;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  bool _isLoading = true;
  String _title = '';
  double _progress = 0;

  /// 「一覧へ戻る」バーの表示フラグ（初期表示あり）
  bool _showBottomBar = true;

  /// スクロール方向検知用の直前 Y 座標
  double _lastScrollY = 0;

  @override
  Widget build(BuildContext context) {
    final barHeight = 72.0 + MediaQuery.of(context).padding.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
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
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: const Color(0xFFAA0000),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              clearCache: false,
            ),
            // ページ読み込み後に click イベントを監視する UserScript を注入。
            // ユーザーが画面をタップすると Flutter ハンドラ 'onTap' が呼ばれ
            // 「一覧へ戻る」バーを再表示する。
            initialUserScripts: widget.showBackToList
                ? UnmodifiableListView([
                    UserScript(
                      source: '''
                        document.addEventListener('click', function() {
                          if (window.flutter_inappwebview) {
                            window.flutter_inappwebview.callHandler('onTap');
                          }
                        });
                      ''',
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                  ])
                : UnmodifiableListView([]),
            onWebViewCreated: (controller) {
              if (!widget.showBackToList) return;
              controller.addJavaScriptHandler(
                handlerName: 'onTap',
                callback: (_) {
                  if (mounted && !_showBottomBar) {
                    setState(() => _showBottomBar = true);
                  }
                },
              );
            },
            // iOS の WKWebView は http/https 以外のスキームへのリダイレクトを
            // 処理できず無限ローディングになるためキャンセルする。
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final scheme = navigationAction.request.url?.scheme ?? '';
              if (scheme != 'http' && scheme != 'https' &&
                  scheme != 'about' && scheme != 'javascript') {
                if (mounted) setState(() => _isLoading = false);
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
            onLoadStart: (controller, url) {
              if (mounted) setState(() => _isLoading = true);
            },
            onProgressChanged: (controller, progress) {
              if (mounted) setState(() => _progress = progress / 100.0);
            },
            onLoadStop: (controller, url) async {
              final title = await controller.getTitle();
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _title = title ?? widget.url;
                });
              }
            },
            onReceivedHttpError: (controller, request, errorResponse) {
              if (mounted) setState(() => _isLoading = false);
            },
            onReceivedError: (controller, request, error) {
              if (mounted) setState(() => _isLoading = false);
            },
            // 下スクロール（y 増加）でバーを非表示。
            // 再表示はスクロールではなく画面タップで行う。
            onScrollChanged: (controller, x, y) {
              if (!widget.showBackToList) return;
              final delta = y - _lastScrollY;
              _lastScrollY = y.toDouble();
              if (delta.abs() < 5) return;
              if (delta > 0 && mounted && _showBottomBar) {
                setState(() => _showBottomBar = false);
              }
            },
          ),
          if (widget.showBackToList)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              left: 0,
              right: 0,
              bottom: _showBottomBar ? 0 : -barHeight,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
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
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 24),
                              textStyle: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600),
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
              ),
            ),
        ],
      ),
    );
  }
}
