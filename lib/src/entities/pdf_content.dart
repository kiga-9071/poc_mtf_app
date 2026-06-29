import 'dart:io';

/// コンテンツ一覧に表示するPDFコンテンツのデータモデル。
/// contents.json の各エントリーに対応する。
class PdfContent {
  const PdfContent({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.url,
    required this.previewImageAsset,
  });

  /// コンテンツの一意な識別子（ファイル名生成に使用）
  final String id;

  /// 表示タイトル
  final String title;

  /// 概要説明文
  final String description;

  /// カテゴリー名（バッジとして表示）
  final String category;

  /// PDFのダウンロードURL
  final String url;

  /// ローカルモード時に参照するアセットパス（URL のファイル名から導出）
  String get assetPath {
    final filename = url.split('/').last;
    return 'assets/pdfs/$filename';
  }

  /// プレビュー画像のアセットパス（将来的にはAPIから取得した画像URLに置き換え予定）
  final String previewImageAsset;

  /// JSONオブジェクトから PdfContent インスタンスを生成するファクトリコンストラクタ。
  factory PdfContent.fromJson(Map<String, dynamic> json) => PdfContent(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        category: json['category'] as String,
        url: json['url'] as String,
        previewImageAsset: json['previewImage'] as String? ??
            'assets/previews/${json['id']}.png',
      );
}

/// ダウンロード済みPDFのローカル保存パスを生成する。
/// ファイル名に言語コードを含めることで、同じIDの日本語版と英語版を
/// 別ファイルとして共存させる（例: 1_ja_DX入門.pdf / 1_en_DX_Guide.pdf）。
String buildSavePath(Directory dir, PdfContent content, String langCode) {
  // タイトルから記号を除去しスペースをアンダースコアに変換
  final sanitized = content.title
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');
  return '${dir.path}/${content.id}_${langCode}_$sanitized.pdf';
}

/// バイト数を人間が読みやすいファイルサイズ文字列に変換する（B / KB / MB）。
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
