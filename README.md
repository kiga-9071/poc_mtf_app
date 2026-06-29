# pdf_app

pdfrx を使用した PDF ビューアアプリです。

## 動作環境

- Flutter 3.44.0 以上 / Dart 3.12.0 以上
- Python 3.8 以上（ローカルサーバー用）
- FVM を使用する場合: `fvm use 3.44.2`

---

## Python のインストール

サーバー起動スクリプト（`start_server.py` / `generate_pdfs.py`）に Python 3.8 以上が必要です。

### macOS

Homebrew を使う方法が最も簡単です。

```bash
# Homebrew 未インストールの場合
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Python をインストール
brew install python

# バージョン確認
python3 --version
```

> **補足**: macOS には `/usr/bin/python3` がプリインストールされていますが、  
> バージョンが古い場合があるため Homebrew 版の使用を推奨します。

### Windows

公式サイトからインストーラーをダウンロードしてください。

1. [https://www.python.org/downloads/](https://www.python.org/downloads/) にアクセス
2. **「Download Python 3.x.x」** をクリックしてインストーラーを取得
3. インストーラーを実行し、**「Add Python to PATH」** にチェックを入れてインストール
4. コマンドプロンプトでバージョンを確認

```cmd
python --version
```

### Python ライブラリのインストール

`generate_pdfs.py` の実行には `reportlab` が必要です。

```bash
pip3 install reportlab
# Windows の場合
pip install reportlab
```

---

## セットアップ

### 1. 依存パッケージのインストール

```bash
flutter pub get
# FVM の場合
fvm flutter pub get
```

---

## サーバーの起動

コンテンツ一覧の PDF は **ローカル HTTP サーバー（port 8765）** から配信されます。  
アプリを「サーバーモード」で使う場合は、事前にサーバーを起動してください。

### 基本手順

```bash
# ① リッチな PDF を pdf_server/ に生成する（初回・PDF を更新したいとき）
python3 generate_pdfs.py

# ② HTTP サーバーを起動する
python3 start_server.py
```

`start_server.py` は以下の優先順位で PDF を準備します。

| 優先順位 | 条件 | 動作 |
|---|---|---|
| 1 | `assets/pdfs/` に同名ファイルがある | そのままコピーして配信 |
| 2 | `pdf_server/` に既にファイルがある | そのまま使用 |
| 3 | どちらにもない | プレースホルダー PDF を自動生成 |

サーバーを停止するには `Ctrl+C` を押してください。

### 配信される PDF

| ファイル | 内容 |
|---|---|
| `dx_guide_jp.pdf` / `dx_guide_en.pdf` | DX 入門ガイド（目次・内部リンク付き、8 ページ） |
| `ai_society_report.pdf` / `ai_society_en.pdf` | AI と社会レポート（外部リンク付き、7〜9 ページ） |
| `text_sample_jp.pdf` / `text_sample_en.pdf` | テキスト形式サンプル（検索・選択・コピー確認用、4 ページ） |
| `image_sample_jp.pdf` / `image_sample_en.pdf` | 画像形式サンプル（グラフ・図形のみ、4 ページ） |

### Android 実機でテストする場合

実機からホスト PC のサーバーへ接続するために `adb reverse` が必要です。  
サーバーを起動した**後**、別ターミナルで以下を実行してください。

```bash
adb reverse tcp:8765 tcp:8765
```

---

## アプリの起動

### iOS シミュレータ

```bash
flutter run -d ios
# FVM の場合
fvm flutter run -d ios
```

### Android エミュレータ / 実機

```bash
flutter run -d android
# FVM の場合
fvm flutter run -d android
```

### 接続済みデバイスを選択

```bash
flutter devices          # デバイス一覧を確認
flutter run -d <device-id>
```

---

## ソースモード切替

アプリ下部のセグメントボタンで PDF の取得元を切り替えられます。

| モード | 取得元 | サーバー起動 |
|---|---|---|
| **サーバー** | `http://localhost:8765/` | 必要 |
| **ローカル** | `assets/pdfs/` に同梱された PDF | 不要 |

---

## 主な機能

- PDF のページ表示（横スワイプでページ切り替え）
- ピンチズーム・パン操作
- ズーム時のミニマップ（2 倍以上で右上に表示）
- キーワード検索・ハイライト表示
- テキスト選択・コピー
- ブックマーク・メモ（ページ単位）
- 目次・内部リンク・外部リンク
- ダークモード対応
- 日本語 / 英語 UI 切替
