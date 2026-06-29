import 'package:flutter/material.dart';

/// アプリ内の多言語文字列を一元管理するクラス。
/// `AppL10n.of(context)` でウィジェットツリーのどこからでもアクセスできる。
/// 対応言語: 日本語（ja）/ 英語（en）
class AppL10n {
  const AppL10n(this.locale);

  // 現在適用されているロケール（言語情報）
  final Locale locale;

  /// ウィジェットツリーから AppL10n インスタンスを取得するヘルパー。
  /// MaterialApp の localizationsDelegates に AppL10n.delegate を登録済みであること。
  static AppL10n of(BuildContext context) =>
      Localizations.of<AppL10n>(context, AppL10n)!;

  /// Flutter の Localizations システムへの登録用デリゲート。
  static const delegate = _AppL10nDelegate();

  // 日本語かどうかを判定するフラグ（文字列切り替えに使用）
  bool get _ja => locale.languageCode == 'ja';

  // ── 共通 ─────────────────────────────────────────────────────────────────

  /// アプリのタイトル
  String get appTitle => 'PDF Viewer';

  /// 言語設定メニューのラベル
  String get language => _ja ? '言語' : 'Language';

  /// 日本語の選択肢表示名
  String get languageJa => '日本語';

  /// 英語の選択肢表示名
  String get languageEn => 'English';

  /// キャンセルボタンのラベル
  String get cancel => _ja ? 'キャンセル' : 'Cancel';

  /// 削除ボタンのラベル
  String get delete => _ja ? '削除' : 'Delete';

  /// PDF取得元モードのラベル
  String get sourceMode => _ja ? 'PDFソース' : 'PDF Source';

  /// サーバーからダウンロードするモードのラベル
  String get sourceModeServer => _ja ? 'サーバー' : 'Server';

  /// アプリ内蔵PDFを使うモードのラベル
  String get sourceModeLocal => _ja ? '内蔵PDF' : 'Built-in';

  /// 開くボタンのラベル
  String get open => _ja ? '開く' : 'Open';

  /// ページ単位を表す文字列（例: "3 ページ"）
  String get page => _ja ? 'ページ' : 'page';

  /// 端末ストレージからファイルを開くボタンのラベル
  String get openFromDevice => _ja ? '端末から開く' : 'Open from Device';

  // ── コンテンツ一覧画面 ────────────────────────────────────────────────────

  /// コンテンツ一覧画面のタイトル
  String get contentList => _ja ? 'コンテンツ一覧' : 'Content List';

  /// ダウンロード済みを示すバッジのラベル
  String get saved => _ja ? '保存済み' : 'Saved';

  /// ダウンロードボタンのラベル
  String get downloadAndSave => _ja ? 'ダウンロード' : 'Download';

  /// ファイル削除ダイアログのタイトル
  String get deleteFile => _ja ? 'ファイルを削除' : 'Delete File';

  /// ファイル削除の確認メッセージ（タイトルを埋め込む）
  String deleteConfirm(String title) => _ja
      ? '「$title」を削除しますか？\nダウンロードし直すことができます。'
      : 'Delete "$title"?\nYou can download it again later.';

  /// ダウンロード中のラベル
  String get downloading => _ja ? 'ダウンロード中...' : 'Downloading...';

  /// ダウンロード失敗時のエラーメッセージ（エラー内容を埋め込む）
  String downloadFailed(String msg) =>
      _ja ? 'ダウンロード失敗: $msg' : 'Download failed: $msg';

  /// 汎用エラーメッセージ（エラー内容を埋め込む）
  String errorMsg(String msg) => _ja ? 'エラー: $msg' : 'Error: $msg';

  /// ファイル削除完了後のスナックバーメッセージ（タイトルを埋め込む）
  String deletedMsg(String title) =>
      _ja ? '「$title」を削除しました' : '"$title" deleted';

  /// コンテンツ読み込みエラーのメッセージ（エラー内容を埋め込む）
  String loadError(String err) =>
      _ja ? '読み込みエラー: $err' : 'Load error: $err';

  // ── PDFビューアー画面 ─────────────────────────────────────────────────────

  /// 一覧画面に戻るボタンのツールチップ
  String get backToList => _ja ? '一覧に戻る' : 'Back to List';

  /// サイドメニューのラベル（ドロワーヘッダーにも使用）
  String get menuLabel => _ja ? 'メニュー' : 'Menu';

  /// 目次タブのラベル
  String get tableOfContents => _ja ? '目次' : 'Contents';

  /// ブックマークタブのラベル
  String get bookmarks => _ja ? 'ブックマーク' : 'Bookmarks';

  /// 検索タブのラベル
  String get search => _ja ? '検索' : 'Search';

  /// 目次が存在しない場合のメッセージ
  String get noTableOfContents => _ja ? '目次がありません' : 'No table of contents';

  /// ブックマークが未登録の場合のメッセージ
  String get noBookmarks => _ja ? 'ブックマークがありません' : 'No bookmarks';

  /// 検索テキストフィールドのヒントテキスト
  String get searchHint => _ja ? 'キーワードを入力...' : 'Enter keyword...';

  /// キーワード検索中のローディングメッセージ
  String get searching => _ja ? '検索中...' : 'Searching...';

  /// 検索結果が0件のメッセージ
  String get noSearchResults =>
      _ja ? '一致するページがありません' : 'No matching pages found';

  /// ブックマーク追加ボタンのツールチップ
  String get addBookmark => _ja ? 'ブックマーク追加' : 'Add Bookmark';

  /// ブックマーク解除ボタンのツールチップ
  String get removeBookmark => _ja ? 'ブックマーク解除' : 'Remove Bookmark';

  /// PDFを開くボタンのラベル
  String get openPdf => _ja ? 'PDFを開く' : 'Open PDF';

  /// PDFが未選択の場合のメッセージ
  String get selectPdf =>
      _ja ? 'PDFファイルを選択してください' : 'Please select a PDF file';

  /// 検索ナビバーを閉じるボタンのツールチップ
  String get closeSearch => _ja ? '検索を閉じる' : 'Close Search';

  /// 前の検索結果へ移動するボタンのツールチップ
  String get prevResult => _ja ? '前の結果' : 'Previous';

  /// 次の検索結果へ移動するボタンのツールチップ
  String get nextResult => _ja ? '次の結果' : 'Next';

  /// ページ番号の表示形式（例: "3 / 10"）
  String pageOf(int current, int total) => '$current / $total';

  /// メモタブのラベル
  String get memo => _ja ? 'メモ' : 'Memo';

  /// メモが未登録の場合のメッセージ
  String get noMemos => _ja ? 'メモがありません' : 'No memos';

  /// メモ追加ボタンのツールチップ
  String get addMemo => _ja ? 'メモを追加' : 'Add Memo';

  /// メモ編集ボタンのツールチップ
  String get editMemo => _ja ? 'メモを編集' : 'Edit Memo';

  /// メモ入力欄のヒントテキスト
  String get memoHint => _ja ? 'このページのメモを入力...' : 'Enter memo for this page...';

  /// 保存ボタンのラベル
  String get save => _ja ? '保存' : 'Save';

  /// WebView でブラウザを開くボタンのラベル
  String get openInBrowser => _ja ? 'ブラウザで開く' : 'Open in Browser';

  /// URLコピー通知メッセージのプレフィックス
  String get urlCopied => _ja ? 'URL: ' : 'URL: ';

  // ── 表示モード切替 ────────────────────────────────────────────────────────

  /// グリッドプレビュー表示に切り替えるボタンのツールチップ
  String get switchToPreview => _ja ? 'プレビュー表示' : 'Preview View';

  /// テキストリスト表示に切り替えるボタンのツールチップ
  String get switchToList => _ja ? 'リスト表示' : 'List View';

  /// プレビューカードでPDF未ダウンロード時に表示するラベル
  String get notDownloaded => _ja ? '未ダウンロード' : 'Not Downloaded';

  // ── テーマ設定 ────────────────────────────────────────────────────────────

  /// テーマ設定ダイアログのタイトル
  String get themeLabel => _ja ? 'テーマ' : 'Theme';

  /// ダークモード選択肢のラベル
  String get themeDark => _ja ? 'ダーク' : 'Dark';

  /// ライトモード選択肢のラベル
  String get themeLight => _ja ? 'ライト' : 'Light';

  /// システム設定に従う選択肢のラベル
  String get themeSystem => _ja ? 'システム設定' : 'Follow System';
}

/// Flutter の Localizations フレームワークへ AppL10n を登録するデリゲート。
/// MaterialApp の localizationsDelegates リストに追加して使用する。
class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  // このデリゲートがサポートする言語コードのセット
  static const _supported = {'ja', 'en'};

  /// 指定ロケールをサポートするかどうかを返す
  @override
  bool isSupported(Locale locale) =>
      _supported.contains(locale.languageCode);

  /// ロケールに対応した AppL10n インスタンスを生成して返す
  @override
  Future<AppL10n> load(Locale locale) =>
      Future.value(AppL10n(locale));

  /// デリゲート自体が変わっていないため常に false を返す（再ロード不要）
  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}
