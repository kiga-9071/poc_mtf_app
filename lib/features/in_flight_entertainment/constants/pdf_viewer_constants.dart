import 'package:flutter/material.dart';

/// PDFビューアー全体で共有するブランドカラー（赤）
const kPdfRedPrimary = Color(0xFFCC0000);

/// サムネイルストリップの画像高さ（px）
const kPdfThumbnailHeight = 100.0;

/// サムネイルストリップの画像幅（px）
const kPdfThumbnailWidth = 70.0;

/// AppBarとサムネイルバーのスライドアニメーション時間
const kPdfBarDuration = Duration(milliseconds: 250);

/// TTS（読み上げ）の状態
enum TtsStatus { idle, loading, speaking }

/// ダークモード時にPDFページ画像の色を反転させるカラーフィルター。
/// 白背景→黒背景・黒文字→白文字 に変換する 4×5 の RGBA カラーマトリクス。
/// アルファ値は変更しないため半透明コンテンツはそのまま維持される。
const kPdfInvertColorFilter = ColorFilter.matrix(<double>[
  -1,  0,  0, 0, 255, // R チャンネルを反転
   0, -1,  0, 0, 255, // G チャンネルを反転
   0,  0, -1, 0, 255, // B チャンネルを反転
   0,  0,  0, 1,   0, // A チャンネルはそのまま
]);
