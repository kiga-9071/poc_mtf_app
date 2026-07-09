import 'package:flutter/material.dart';

// ── データ ────────────────────────────────────────────────────────────────────

class _ShopProduct {
  const _ShopProduct({
    required this.title,
    required this.price,
    required this.rating,
    required this.reviewCount,
  });
  final String title;
  final String price;
  final double rating;
  final int reviewCount;
}

const _sampleProducts = [
  _ShopProduct(
    title: 'シングルモルト 遊佐 ミズナラカスク',
    price: '¥4,500',
    rating: 4.5,
    reviewCount: 23,
  ),
  _ShopProduct(
    title: 'LOHME クワイエットマニッシュチェーンネックレス',
    price: '¥8,800',
    rating: 4.2,
    reviewCount: 15,
  ),
  _ShopProduct(
    title: 'ファミリア JALオリジナル フライトタグ',
    price: '¥2,200',
    rating: 4.8,
    reviewCount: 42,
  ),
  _ShopProduct(
    title: '『トイ・ストーリー』JALオリジナル',
    price: '¥3,300',
    rating: 4.6,
    reviewCount: 31,
  ),
];

// ── ShopTab ───────────────────────────────────────────────────────────────────

/// SHOP タブのルートウィジェット。
/// サブタブ（おすすめ / 新着 / カテゴリー）と商品グリッドを表示する。
class ShopTab extends StatelessWidget {
  const ShopTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      initialIndex: 1,
      child: Column(
        children: [
          // ── サブタブバー ──────────────────────────────────────────────────
          Material(
            elevation: 0,
            child: TabBar(
              labelColor: Color(0xFFCC0000),
              unselectedLabelColor: Color(0xFF666666),
              indicatorColor: Color(0xFFCC0000),
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              unselectedLabelStyle: TextStyle(
                fontWeight: FontWeight.w400,
                fontSize: 14,
              ),
              tabs: [
                Tab(text: 'おすすめ'),
                Tab(text: '新着'),
                Tab(text: 'カテゴリー'),
              ],
            ),
          ),
          // ── コンテンツ ────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              children: [
                _ShopProductList(),
                _ShopProductList(),
                _ShopProductList(),
              ],
            ),
          ),

        ],
      ),
    );
  }
}

// ── _ShopProductList ──────────────────────────────────────────────────────────

class _ShopProductList extends StatelessWidget {
  const _ShopProductList();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // ── セクションヘッダー ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(25, 16, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'ご搭乗のお客様限定',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    height: 1.5,
                    color: Color(0xFF000000),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.favorite_border, size: 18),
                  label: const Text('お気に入り'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2A344B),
                    side: const BorderSide(color: Color(0xFFB7C1CD)),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── 商品グリッド（2カラム）────────────────────────────────────────
        // Figma: 左 left=25px、右 left=204px、カード幅163px、カラム間16px
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 163 / 309,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _ShopProductCard(
                product: _sampleProducts[index % _sampleProducts.length],
              ),
              childCount: 8,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

// ── _ShopProductCard ──────────────────────────────────────────────────────────

class _ShopProductCard extends StatelessWidget {
  const _ShopProductCard({required this.product});
  final _ShopProduct product;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 商品画像（163×163）
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Icon(
                Icons.shopping_bag_outlined,
                size: 40,
                color: Colors.grey[400],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 商品名（太字 14px、2行まで）
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.5,
                  color: Color(0xFF000000),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // 価格・レビューエリア
              _PriceArea(product: product),
            ],
          ),
        ),
      ],
    );
  }
}

// ── _PriceArea ────────────────────────────────────────────────────────────────

class _PriceArea extends StatelessWidget {
  const _PriceArea({required this.product});
  final _ShopProduct product;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 星評価 + レビュー数
        Row(
          children: [
            ...List.generate(5, (i) {
              final full = i < product.rating.floor();
              final half = !full && i < product.rating;
              return Icon(
                full
                    ? Icons.star
                    : half
                        ? Icons.star_half
                        : Icons.star_border,
                size: 13,
                color: const Color(0xFFCC0000),
              );
            }),
            const SizedBox(width: 4),
            Text(
              '(${product.reviewCount})',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF666666),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 価格
        Text(
          product.price,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Color(0xFF000000),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          '税込',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF666666),
          ),
        ),
      ],
    );
  }
}
