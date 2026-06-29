/// キーワード検索の1件ヒット情報を表すレコード型。
///
/// - pageNumber : ヒットが存在するページ番号（1始まり）
/// - charStart  : ページ全文テキスト内のヒット開始文字インデックス
/// - charEnd    : ページ全文テキスト内のヒット終了文字インデックス（排他）
///
/// charStart / charEnd は PdfSearchHighlightOverlay でハイライト矩形を
/// 計算する際に使用する。
typedef SearchMatch = ({int pageNumber, int charStart, int charEnd});
