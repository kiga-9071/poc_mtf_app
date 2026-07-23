import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../entities/search_match.dart';

/// PDFファイル全体をキーワード検索し、ヒット箇所の一覧を返す関数。
///
/// [query]       : 検索キーワード文字列
/// [filePath]    : ローカルPDFファイルのパス
/// [isCancelled] : 途中キャンセルを確認するコールバック（true を返すと中断）
///
/// 戻り値: 全ヒットの [SearchMatch] リスト。
/// キャンセル時は中断時点までの結果または空リストを返す。
///
/// 内部でPDFドキュメントを独立して開くため、ビューアー表示中の
/// ドキュメントと干渉しない。
Future<List<SearchMatch>> performPdfSearch({
  required String query,
  required String filePath,
  required bool Function() isCancelled,
}) async {
  final matches = <SearchMatch>[];
  // 大文字小文字を区別しない検索パターン（クエリ文字列を正規表現エスケープ）
  final pattern = RegExp(RegExp.escape(query), caseSensitive: false);

  // 検索専用のPdfDocumentを開く（ビューアー表示用ドキュメントとは別インスタンス）
  PdfDocument? doc;
  try {
    doc = await PdfDocument.openFile(filePath);
    if (isCancelled()) return matches;

    // 全ページのテキストを順に走査
    for (int i = 0; i < doc.pages.length; i++) {
      if (isCancelled()) break;
      try {
        final pageText = await doc.pages[i].loadText();
        if (isCancelled()) break;
        // ページ全文テキスト内でパターンにマッチする全箇所を取得
        for (final m in pattern.allMatches(pageText.fullText)) {
          matches.add((
            pageNumber: i + 1,
            charStart: m.start,
            charEnd: m.end,
          ));
        }
      } catch (_) {
        // CIDフォント等でテキスト抽出に失敗した場合はスキップ
      }
    }
  } catch (e) {
    debugPrint('[SearchController] PdfDocument open error: $e');
  } finally {
    doc?.dispose(); // 検索専用ドキュメントを確実に破棄
  }

  return matches;
}
