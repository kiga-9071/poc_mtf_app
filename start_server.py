#!/usr/bin/env python3
"""
ローカル開発用 PDF サーバー (port 8765)

Usage:
    python start_server.py

PDF ファイルを pdf_server/ ディレクトリに配置するか、
このスクリプトが自動生成するプレースホルダーを使用してください。

Android 実機でテストする場合は事前に以下を実行してください:
    adb reverse tcp:8765 tcp:8765
"""

import http.server
import os
import sys

PORT = 8765
SERVE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pdf_server")

# (ファイル名, タイトル, ページ数) — contents.json と対応
# generate_pdfs.py で生成したリッチ PDF が pdf_server/ に無い場合のプレースホルダー
PDF_FILES = [
    ("dx_guide_jp.pdf",       "DX Guide (Sample)",                8),
    ("ai_society_report.pdf", "AI Society Report (Sample)",       9),
    ("dx_guide_en.pdf",       "DX Guide EN (Sample)",             8),
    ("ai_society_en.pdf",     "AI Society EN (Sample)",           7),
    ("text_sample_jp.pdf",    "Text Format Sample JP (Sample)",   4),
    ("text_sample_en.pdf",    "Text Format Sample EN (Sample)",   4),
    ("image_sample_jp.pdf",   "Image Format Sample JP (Sample)",  4),
    ("image_sample_en.pdf",   "Image Format Sample EN (Sample)",  4),
]

# assets/pdfs/ に同名ファイルがあればそちらをコピー元として優先する
ASSETS_PDF_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "pdfs")


def _make_pdf(title: str, page_count: int) -> bytes:
    """複数ページの PDF バイト列を生成する。"""
    safe = title.encode("ascii", errors="replace").decode("ascii")
    safe = safe.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")

    # オブジェクト番号の割り当て
    # 1: Catalog  2: Pages
    # 3+2*i: Page i+1  4+2*i: Content stream i+1
    # 3+2*N: Font
    font_n = 3 + 2 * page_count
    page_ns = [3 + 2 * i for i in range(page_count)]
    cont_ns = [4 + 2 * i for i in range(page_count)]
    kids = " ".join(f"{n} 0 R" for n in page_ns)

    def make_obj(n: int, body: bytes) -> bytes:
        return f"{n} 0 obj\n".encode() + body + b"\nendobj\n"

    pieces: list[bytes] = [b"%PDF-1.4\n"]
    offsets: dict[int, int] = {}
    pos = len(pieces[0])

    def add(n: int, body: bytes) -> None:
        nonlocal pos
        data = make_obj(n, body)
        offsets[n] = pos
        pieces.append(data)
        pos += len(data)

    add(1, b"<< /Type /Catalog /Pages 2 0 R >>")
    add(2, f"<< /Type /Pages /Kids [{kids}] /Count {page_count} >>".encode())

    for i in range(page_count):
        pg, ct, page_n = page_ns[i], cont_ns[i], i + 1
        add(pg, (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842]"
            f" /Contents {ct} 0 R"
            f" /Resources << /Font << /F1 {font_n} 0 R >> >> >>"
        ).encode())

        stream = (
            f"BT /F1 18 Tf 50 780 Td ({safe}) Tj"
            f" /F1 13 Tf 0 -36 Td (Page {page_n} / {page_count}) Tj ET"
        ).encode("latin-1")
        add(ct, f"<< /Length {len(stream)} >>\nstream\n".encode() + stream + b"\nendstream")

    add(font_n, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    body = b"".join(pieces)
    xref_pos = len(body)
    xref = f"xref\n0 {font_n + 1}\n".encode()
    xref += b"0000000000 65535 f \n"
    for n in range(1, font_n + 1):
        xref += f"{offsets[n]:010d} 00000 n \n".encode()
    trailer = (
        f"trailer\n<< /Size {font_n + 1} /Root 1 0 R >>\nstartxref\n{xref_pos}\n%%EOF\n"
    ).encode()

    return body + xref + trailer


def ensure_pdf_dir() -> None:
    """pdf_server/ が無ければ作成し、PDF ファイルを準備する。

    優先順位:
      1. assets/pdfs/ に同名ファイルがあればコピー（リッチ版）
      2. pdf_server/ に既にファイルがあればそのまま使用
      3. どちらも無ければプレースホルダー PDF を生成
    """
    import shutil
    os.makedirs(SERVE_DIR, exist_ok=True)
    for filename, title, pages in PDF_FILES:
        dest = os.path.join(SERVE_DIR, filename)
        asset = os.path.join(ASSETS_PDF_DIR, filename)
        if os.path.exists(asset):
            shutil.copy2(asset, dest)
            print(f"  [コピー] {filename}  ← assets/pdfs/")
        elif os.path.exists(dest):
            print(f"  [既存]  {filename}")
        else:
            with open(dest, "wb") as f:
                f.write(_make_pdf(title, pages))
            print(f"  [生成]  {filename} ({pages} pages) ※プレースホルダー")


class _Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=SERVE_DIR, **kwargs)

    def log_message(self, fmt, *args):  # type: ignore[override]
        print(f"  → {self.address_string()} {fmt % args}")


if __name__ == "__main__":
    print(f"PDF サーバー起動中 (port {PORT})")
    print(f"配信ディレクトリ: {SERVE_DIR}\n")
    print("PDF ファイルを生成中...")
    ensure_pdf_dir()
    print(f"\nサーバー起動完了: http://localhost:{PORT}/")
    print("停止するには Ctrl+C を押してください。\n")

    try:
        with http.server.HTTPServer(("", PORT), _Handler) as httpd:
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nサーバーを停止しました。")
        sys.exit(0)
