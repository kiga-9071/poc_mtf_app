/// PDFビューアーへの遷移時に go_router の extra として渡す引数。
class ViewerArgs {
  const ViewerArgs({
    this.filePath,
    this.preventCapture = false,
  });

  /// 開くローカルファイルのパス（null = ファイル未選択状態でビューアーを起動）
  final String? filePath;

  /// スクリーンショット・録画を OS レベルで抑止するかどうか
  final bool preventCapture;
}
