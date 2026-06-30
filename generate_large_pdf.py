#!/usr/bin/env python3
"""
バックグラウンドダウンロード検証用の大容量 PDF を生成するスクリプト。

各ページに非圧縮の RGB 画像データを埋め込み、合計で指定サイズ以上のファイルを生成する。
圧縮フィルターを使わないことで PDF 自体のサイズを確保する。

Usage:
    python generate_large_pdf.py
"""

import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "pdf_server", "large_test.pdf")

# 1 ページあたりの画像サイズ（A4 換算で十分な解像度）
IMG_W = 1024   # pixels
IMG_H = 1024   # pixels
PAGE_COUNT = 67  # ページ数
# 1024 * 1024 * 3 bytes * 67 pages ≈ 204 MB


def _make_image_data(img_w: int, img_h: int, page_idx: int) -> bytes:
    """各ページ固有のグラデーションパターンを生成する（圧縮されにくいデータ）。"""
    size = img_w * img_h * 3
    seed = page_idx * 7 + 3
    # ページ番号によって色調が変わるグラデーション
    data = bytearray(size)
    for i in range(img_w * img_h):
        x = i % img_w
        y = i // img_w
        data[i * 3 + 0] = (x * 251 // img_w + seed * 37) % 256          # R
        data[i * 3 + 1] = (y * 241 // img_h + seed * 53 + 85) % 256     # G
        data[i * 3 + 2] = ((x + y) * 233 // (img_w + img_h) + seed * 71 + 170) % 256  # B
    return bytes(data)


def generate_large_pdf(path: str, img_w: int, img_h: int, page_count: int) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)

    parts: list[bytes] = [b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n']
    pos = len(parts[0])
    offsets: dict[int, int] = {}

    def write_obj(num: int, body: bytes) -> None:
        nonlocal pos
        chunk = f'{num} 0 obj\n'.encode() + body + b'\nendobj\n'
        offsets[num] = pos
        parts.append(chunk)
        pos += len(chunk)

    # オブジェクト番号の設計:
    #   1: Catalog
    #   2: Pages
    #   3 + 3*i: Page i の辞書
    #   4 + 3*i: Page i のコンテンツストリーム
    #   5 + 3*i: Page i の画像 XObject
    catalog_num = 1
    pages_num = 2
    page_nums    = [3 + 3 * i for i in range(page_count)]
    content_nums = [4 + 3 * i for i in range(page_count)]
    image_nums   = [5 + 3 * i for i in range(page_count)]
    total_objs = 2 + 3 * page_count

    write_obj(catalog_num, f'<< /Type /Catalog /Pages {pages_num} 0 R >>'.encode())

    kids = ' '.join(f'{n} 0 R' for n in page_nums)
    write_obj(pages_num, f'<< /Type /Pages /Kids [{kids}] /Count {page_count} >>'.encode())

    for i in range(page_count):
        page_num    = page_nums[i]
        content_num = content_nums[i]
        image_num   = image_nums[i]

        # 画像 XObject（非圧縮 RGB）
        img_bytes = _make_image_data(img_w, img_h, page_idx=i)
        img_body = (
            f'<< /Type /XObject /Subtype /Image '
            f'/Width {img_w} /Height {img_h} '
            f'/ColorSpace /DeviceRGB /BitsPerComponent 8 '
            f'/Length {len(img_bytes)} >>\n'
            f'stream\n'
        ).encode() + img_bytes + b'\nendstream'
        write_obj(image_num, img_body)

        # コンテンツストリーム（画像をページ全体に描画）
        stream = (
            f'q {595} 0 0 {842} 0 0 cm /Im1 Do Q\n'
            f'BT /F1 14 Tf 40 810 Td (Page {i + 1} / {page_count}  -  Large File Test) Tj ET'
        ).encode()
        content_body = (
            f'<< /Length {len(stream)} >>\nstream\n'
        ).encode() + stream + b'\nendstream'
        write_obj(content_num, content_body)

        # ページ辞書
        page_body = (
            f'<< /Type /Page /Parent {pages_num} 0 R '
            f'/MediaBox [0 0 595 842] '
            f'/Contents {content_num} 0 R '
            f'/Resources << '
            f'/XObject << /Im1 {image_num} 0 R >> '
            f'/Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> '
            f'>> >>'
        ).encode()
        write_obj(page_num, page_body)

        progress = (i + 1) * 100 // page_count
        print(f'\r  生成中... {progress}%', end='', flush=True)

    # xref テーブル
    xref_pos = pos
    xref = f'xref\n0 {total_objs + 1}\n'.encode()
    xref += b'0000000000 65535 f \n'
    for n in range(1, total_objs + 1):
        xref += f'{offsets[n]:010d} 00000 n \n'.encode()

    trailer = (
        f'trailer\n<< /Size {total_objs + 1} /Root {catalog_num} 0 R >>\n'
        f'startxref\n{xref_pos}\n%%EOF\n'
    ).encode()

    content = b''.join(parts) + xref + trailer
    with open(path, 'wb') as f:
        f.write(content)

    size_mb = len(content) / 1024 / 1024
    print(f'\r  [完了] {os.path.basename(path)}: {page_count} ページ, {size_mb:.1f} MB')


if __name__ == '__main__':
    print(f'大容量テスト PDF を生成中...')
    print(f'  画像サイズ: {IMG_W}x{IMG_H} px × {PAGE_COUNT} ページ')
    print(f'  出力先: {OUTPUT_PATH}\n')
    generate_large_pdf(OUTPUT_PATH, IMG_W, IMG_H, PAGE_COUNT)
