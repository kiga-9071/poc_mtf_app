import 'package:flutter/material.dart';

import '../youtube_player/youtube_player_page.dart';

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
    title: '同じ機種のパイロットがサシで語り合ったら意見が割れました【はなそか】',
    channel: 'JAL（日本航空）公式',
    views: '121,543回視聴',
    duration: '24:31',
  ),
  _YoutubeVideo(
    videoId: 'CpyAjyl5lgc',
    title: 'パイロット訓練の裏側に密着！シミュレーターで地上から空へ【JAL公式】',
    channel: 'JAL（日本航空）公式',
    views: '98,210回視聴',
    duration: '18:45',
  ),
  _YoutubeVideo(
    videoId: 'CpyAjyl5lgc',
    title: '客室乗務員が語る！機内サービスのこだわりとは【JALの仕事】',
    channel: 'JAL（日本航空）公式',
    views: '72,384回視聴',
    duration: '15:20',
  ),
  _YoutubeVideo(
    videoId: 'CpyAjyl5lgc',
    title: '787整備士が語る！巨大機体を支える職人技【JAL整備】',
    channel: 'JAL（日本航空）公式',
    views: '56,892回視聴',
    duration: '22:07',
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
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => YoutubePlayerPage(
            videoId: video.videoId,
            title: video.title,
          ),
        ),
      ),
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
          Text(
            '${video.channel}・${video.views}',
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
