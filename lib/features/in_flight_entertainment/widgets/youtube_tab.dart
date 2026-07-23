import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// ── データ ────────────────────────────────────────────────────────────────────

class _YoutubeVideo {
  const _YoutubeVideo({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.views,
    required this.duration,
  });
  final String videoId;
  final String title;
  final String channel;
  final String views;
  final String duration;
}

const _sampleVideos = [
  _YoutubeVideo(
    videoId: 'CpyAjyl5lgc',
    title: '「グアムがあるじゃん！」ホテルステイ編／JALグアム線55周年記念',
    channel: 'JAL（日本航空）公式',
    views: '',
    duration: '',
  ),
  _YoutubeVideo(
    videoId: 'y9uGSHNCPnw',
    title: 'DREAM MILES PASSプロジェクト実施報告ムービー',
    channel: 'JAL（日本航空）公式',
    views: '',
    duration: '',
  ),
  _YoutubeVideo(
    videoId: '2mGi0rQEgMc',
    title: '【着陸から離陸まで密着】飛行機が飛び立つまでの"裏側"｜JAL空港スタッフの仕事に迫る',
    channel: 'JAL（日本航空）公式',
    views: '',
    duration: '',
  ),
];

// ── YoutubeTab ────────────────────────────────────────────────────────────────

/// Youtube【公式】タブのルートウィジェット。動画リストを表示する。
class YoutubeTab extends StatelessWidget {
  const YoutubeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 34, left: 23, right: 23, bottom: 24),
      itemCount: _sampleVideos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 25),
      itemBuilder: (context, index) =>
          _YoutubeVideoCard(video: _sampleVideos[index]),
    );
  }
}

// ── _YoutubeVideoCard ─────────────────────────────────────────────────────────

class _YoutubeVideoCard extends StatelessWidget {
  const _YoutubeVideoCard({required this.video});
  final _YoutubeVideo video;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        // ChromeSafariBrowser = iOS: SFSafariViewController / Android: Custom Tabs
        // 本物のブラウザエンジンで開くため YouTube の WebView 検知を回避できる
        final browser = ChromeSafariBrowser();
        await browser.open(
          url: WebUri('https://www.youtube.com/watch?v=${video.videoId}'),
          settings: ChromeSafariBrowserSettings(
            presentationStyle: ModalPresentationStyle.FULL_SCREEN,
            barCollapsingEnabled: true,
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // サムネイル（343×192、16:9比率）
          AspectRatio(
            aspectRatio: 343 / 192,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    'https://img.youtube.com/vi/${video.videoId}/hqdefault.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 56,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCC0000),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                if (video.duration.isNotEmpty)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        video.duration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            video.title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              height: 1.5,
              color: Color(0xFF000000),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          if (video.views.isNotEmpty)
            Text(
              video.views,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF666666),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
