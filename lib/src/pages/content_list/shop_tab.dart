import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ── データ ────────────────────────────────────────────────────────────────────

class _ShopProduct {
  const _ShopProduct({
    required this.title,
    required this.price,
    required this.rating,
    required this.reviewCount,
    required this.imagePath,
    required this.url,
  });
  final String title;
  final String price;
  final double rating;
  final int reviewCount;
  final String imagePath;
  final String url;
}

const _sampleProducts = [
  _ShopProduct(
    title: 'シングルモルト 遊佐 ミズナラカスク',
    price: '¥4,500',
    rating: 4.5,
    reviewCount: 23,
    imagePath: 'assets/shop_single.png',
    url: 'https://ec.jal.co.jp/shop/g/g0001-60121-02/',
  ),
  _ShopProduct(
    title: 'LOHME クワイエットマニッシュチェーンネックレス',
    price: '¥8,800',
    rating: 4.2,
    reviewCount: 15,
    imagePath: 'assets/shop_lohme.png',
    url: 'https://ec.jal.co.jp/shop/g/g0001-81266-02/',
  ),
  _ShopProduct(
    title: 'ファミリア JALオリジナル フライトタグ',
    price: '¥2,200',
    rating: 4.8,
    reviewCount: 42,
    imagePath: 'assets/shop_famillea.png',
    url: 'https://ec.jal.co.jp/shop/g/g0001-88408-02/',
  ),
  _ShopProduct(
    title: '『トイ・ストーリー』JALオリジナル',
    price: '¥3,300',
    rating: 4.6,
    reviewCount: 31,
    imagePath: 'assets/shop_toystory.png',
    url: 'https://ec.jal.co.jp/shop/g/g0001-88403-02/',
  ),
];

const _allProducts = [
  _ShopProduct(
    title: '玄品 鰻玄の国産うなぎ蒲焼 4本 おまとめセット',
    price: '¥13,500',
    rating: 0,
    reviewCount: 0,
    imagePath: 'assets/shop_unagi.jpg',
    url: 'https://ec.jal.co.jp/shop/g/g0028-69061/',
  ),
  _ShopProduct(
    title: 'iPhone 17 256GB ホワイト',
    price: '¥145,400',
    rating: 0,
    reviewCount: 0,
    imagePath: 'assets/shop_iphone.jpg',
    url: 'https://ec.jal.co.jp/shop/g/g0114-MG684J/',
  ),
  _ShopProduct(
    title: 'JAL特製オリジナルビーフカレー 200g×11食セット',
    price: '¥10,800',
    rating: 0,
    reviewCount: 0,
    imagePath: 'assets/shop_curry.jpg',
    url: 'https://ec.jal.co.jp/shop/g/g0002-4654J/',
  ),
  _ShopProduct(
    title: 'JALオリジナルドリンク スカイタイム（ももとぶどう）6本セット',
    price: '¥2,138',
    rating: 0,
    reviewCount: 0,
    imagePath: 'assets/shop_skytime.jpg',
    url: 'https://ec.jal.co.jp/shop/g/g0002-3391J/',
  ),
];

// ── ShopTab ───────────────────────────────────────────────────────────────────

/// SHOP タブのルートウィジェット。商品グリッドを表示する。
class ShopTab extends StatelessWidget {
  const ShopTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ShopProductList();
  }
}

// ── _ShopTab 切り替えタブ ──────────────────────────────────────────────────────

enum _ShopTabType { limited, all }

// ── _ShopProductList ──────────────────────────────────────────────────────────

class _ShopProductList extends StatefulWidget {
  const _ShopProductList();

  @override
  State<_ShopProductList> createState() => _ShopProductListState();
}

class _ShopProductListState extends State<_ShopProductList> {
  _ShopTabType _selected = _ShopTabType.limited;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // ── 切り替えタブ（Figma: width 342px, height 48px）─────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Container(
              height: 48,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE0E0E0)),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  _TabButton(
                    label: 'ご搭乗のお客様限定',
                    selected: _selected == _ShopTabType.limited,
                    onTap: () =>
                        setState(() => _selected = _ShopTabType.limited),
                  ),
                  _TabButton(
                    label: '商品一覧',
                    selected: _selected == _ShopTabType.all,
                    onTap: () =>
                        setState(() => _selected = _ShopTabType.all),
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── セクションヘッダー ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(25, 16, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _selected == _ShopTabType.limited ? 'ご搭乗のお客様限定' : '商品一覧',
                  style: const TextStyle(
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
          sliver: Builder(builder: (context) {
            final products = _selected == _ShopTabType.limited
                ? _sampleProducts
                : _allProducts;
            return SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 163 / 309,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _ShopProductCard(product: products[index]),
                childCount: products.length,
              ),
            );
          }),
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
    return GestureDetector(
      onTap: () => context.push('/webview', extra: product.url),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 商品画像（163×163）
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.asset(
              product.imagePath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFFF0F0F0),
                child: Center(
                  child: Icon(
                    Icons.shopping_bag_outlined,
                    size: 40,
                    color: Colors.grey[400],
                  ),
                ),
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
      ),
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
        // 星評価 + レビュー数（rating > 0 のときのみ表示）
        if (product.rating > 0) ...[
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
        ],
        // 価格（税込）1行表示
        if (product.price.isNotEmpty)
          Text(
            '${product.price.replaceFirst('¥', '')}円（税込）',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF000000),
            ),
          ),
      ],
    );
  }
}

// ── _TabButton ────────────────────────────────────────────────────────────────

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFCC0000) : Colors.white,
            borderRadius: BorderRadius.circular(23),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF333333),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
