import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/controllers/search_controller.dart';
import '../models/entities/search_match.dart';
import '../../../core/utils/l10n.dart';

/// 目次・ブックマーク・キーワード検索の 3 タブを持つサイドドロワー。
class PdfSideDrawer extends StatefulWidget {
  const PdfSideDrawer({
    super.key,
    required this.outline,
    required this.bookmarks,
    required this.memos,
    required this.filePath,
    required this.onOutlineTap,
    required this.onBookmarkTap,
    required this.onBookmarkDelete,
    required this.onMemoTap,
    required this.onMemoDelete,
    required this.onSearchDone,
  });

  /// PDFの目次ノードリスト（目次タブで表示）
  final List<PdfOutlineNode> outline;

  /// ブックマーク済みページ番号のセット
  final Set<int> bookmarks;

  /// ページ番号→メモテキストのマップ
  final Map<int, String> memos;

  /// 現在開いているPDFのファイルパス（SearchController に渡す）
  final String? filePath;

  /// 目次アイテムタップ時のコールバック
  final void Function(PdfDest dest) onOutlineTap;

  /// ブックマークアイテムタップ時のコールバック
  final ValueChanged<int> onBookmarkTap;

  /// ブックマーク削除ボタンタップ時のコールバック
  final ValueChanged<int> onBookmarkDelete;

  /// メモアイテムタップ時のコールバック（ページへジャンプ）
  final ValueChanged<int> onMemoTap;

  /// メモ削除ボタンタップ時のコールバック
  final ValueChanged<int> onMemoDelete;

  /// 検索完了時のコールバック（クエリとヒット一覧を親ウィジェットに渡す）
  final void Function(String query, List<SearchMatch> matches) onSearchDone;

  @override
  State<PdfSideDrawer> createState() => _PdfSideDrawerState();
}

class _PdfSideDrawerState extends State<PdfSideDrawer>
    with SingleTickerProviderStateMixin {
  /// 目次・ブックマーク・検索タブの切り替えコントローラー
  late TabController _tabController;

  /// 検索キーワード入力フィールドのコントローラー
  final _searchController = TextEditingController();

  /// 検索処理中かどうかのフラグ
  bool _isSearching = false;

  /// 検索結果が0件だったかどうかのフラグ
  bool _noResults = false;

  /// 非同期検索の世代番号。
  /// 検索リクエストごとにインクリメントし、古いリクエストの結果を破棄するために使用する。
  int _searchGen = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchGen++; // ドロワー破棄時に進行中の検索を無効化
    super.dispose();
  }

  /// キーワード検索を実行する。
  /// SearchController の performPdfSearch に処理を委譲し、
  /// 世代番号（_searchGen）でキャンセル管理を行う。
  Future<void> _performSearch(String query) async {
    final myGen = ++_searchGen;

    if (query.trim().isEmpty || widget.filePath == null) {
      if (mounted) setState(() { _isSearching = false; _noResults = false; });
      return;
    }

    if (mounted) setState(() { _isSearching = true; _noResults = false; });

    // SearchController の関数に検索処理を委譲
    final matches = await performPdfSearch(
      query: query,
      filePath: widget.filePath!,
      // 新しい検索が開始されていたら true を返してキャンセル
      isCancelled: () => _searchGen != myGen,
    );

    if (_searchGen != myGen || !mounted) return;

    if (matches.isNotEmpty) {
      // ヒットあり: 親ウィジェットにヒット一覧を渡し、ドロワーを閉じる
      widget.onSearchDone(query, matches);
      Navigator.of(context).pop();
    } else {
      setState(() { _isSearching = false; _noResults = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final headerFg = isDark ? Colors.white : Colors.black;
    final headerFgMuted = isDark ? Colors.white60 : Colors.black54;

    return Drawer(
      child: Column(
        children: [
          // ── ドロワーヘッダー（タイトル + タブバー） ──────────────────────
          DrawerHeader(
            decoration: BoxDecoration(color: headerBg),
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    AppL10n.of(context).menuLabel,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: headerFg),
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  labelColor: headerFg,
                  unselectedLabelColor: headerFgMuted,
                  indicatorColor: headerFg,
                  tabs: [
                    Tab(icon: const Icon(Icons.list),
                        text: AppL10n.of(context).tableOfContents),
                    Tab(icon: const Icon(Icons.bookmark),
                        text: AppL10n.of(context).bookmarks),
                    Tab(icon: const Icon(Icons.edit_note),
                        text: AppL10n.of(context).memo),
                    Tab(icon: const Icon(Icons.search),
                        text: AppL10n.of(context).search),
                  ],
                ),
              ],
            ),
          ),
          // ── タブコンテンツ ────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 目次タブ
                widget.outline.isEmpty
                    ? Center(
                        child: Text(AppL10n.of(context).noTableOfContents))
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: widget.outline
                            .map((node) => PdfOutlineItem(
                                  node: node,
                                  onTap: widget.onOutlineTap,
                                  depth: 0,
                                ))
                            .toList(),
                      ),

                // ブックマークタブ
                widget.bookmarks.isEmpty
                    ? Center(child: Text(AppL10n.of(context).noBookmarks))
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: (widget.bookmarks.toList()..sort())
                            .map((page) => ListTile(
                                  leading: const Icon(Icons.bookmark,
                                      color: Colors.amber),
                                  title: Text(
                                      '$page ${AppL10n.of(context).page}'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20),
                                    onPressed: () =>
                                        widget.onBookmarkDelete(page),
                                  ),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    widget.onBookmarkTap(page);
                                  },
                                ))
                            .toList(),
                      ),

                // メモタブ
                widget.memos.isEmpty
                    ? Center(child: Text(AppL10n.of(context).noMemos))
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: (widget.memos.entries.toList()
                              ..sort((a, b) => a.key.compareTo(b.key)))
                            .map((entry) => ListTile(
                                  leading: const Icon(Icons.edit_note,
                                      color: Colors.lightBlue),
                                  title: Text(
                                      '${entry.key} ${AppL10n.of(context).page}'),
                                  subtitle: Text(
                                    entry.value,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20),
                                    onPressed: () =>
                                        widget.onMemoDelete(entry.key),
                                  ),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    widget.onMemoTap(entry.key);
                                  },
                                ))
                            .toList(),
                      ),

                // 検索タブ
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: AppL10n.of(context).searchHint,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchController.clear();
                                        _performSearch('');
                                      },
                                    )
                                  : null,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.search,
                        // 文字入力時は「見つかりません」メッセージをクリアするだけ
                        onChanged: (v) =>
                            setState(() { _noResults = false; }),
                        // エンターキーで検索を実行
                        onSubmitted: _performSearch,
                        enabled: widget.filePath != null,
                      ),
                    ),
                    if (_isSearching)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Text(AppL10n.of(context).searching,
                                style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      )
                    else if (_noResults)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Text(
                          AppL10n.of(context).noSearchResults,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.red),
                        ),
                      ),
                    const Spacer(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── PdfOutlineItem ────────────────────────────────────────────────────────────

/// 目次の1アイテムを表示するウィジェット。
/// 子ノードがある場合は展開/折りたたみが可能。
/// 深さ（depth）に応じてインデントを加えて階層構造を視覚化する。
class PdfOutlineItem extends StatefulWidget {
  const PdfOutlineItem({
    super.key,
    required this.node,
    required this.onTap,
    required this.depth,
  });

  final PdfOutlineNode node;
  final void Function(PdfDest dest) onTap;

  /// 階層の深さ（0 = トップレベル、インデント量の計算に使用）
  final int depth;

  @override
  State<PdfOutlineItem> createState() => _PdfOutlineItemState();
}

class _PdfOutlineItemState extends State<PdfOutlineItem> {
  /// 子ノードを展開しているかどうかのフラグ
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasChildren = widget.node.children.isNotEmpty;
    // 深さに応じた左インデント量（1階層ごとに 16px 加算）
    final indent = widget.depth * 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: 16 + indent, right: 8),
          title: Text(
            widget.node.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: widget.depth == 0
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
          trailing: hasChildren
              ? IconButton(
                  icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () =>
                      setState(() => _expanded = !_expanded),
                )
              : null,
          onTap: widget.node.dest != null
              ? () {
                  Navigator.of(context).pop();
                  widget.onTap(widget.node.dest!);
                }
              : null,
        ),
        if (hasChildren && _expanded)
          ...widget.node.children.map(
            (child) => PdfOutlineItem(
              node: child,
              onTap: widget.onTap,
              depth: widget.depth + 1,
            ),
          ),
      ],
    );
  }
}
