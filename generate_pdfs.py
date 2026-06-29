#!/usr/bin/env python3
"""
テスト用 PDF ファイルを生成するスクリプト。
目次・内部リンク・外部リンクを含む PDF を pdf_server/ に出力します。

Usage:
    python generate_pdfs.py
"""

import os
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from reportlab.lib.colors import HexColor, white, black
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pdf_server")
W, H = A4  # 595 x 842 pt

BLUE   = HexColor("#1a4b8c")
LBLUE  = HexColor("#d0e4f7")
GRAY   = HexColor("#555555")
LGRAY  = HexColor("#f0f0f0")
LINK_COLOR = HexColor("#1155cc")


def register_fonts():
    pdfmetrics.registerFont(UnicodeCIDFont("HeiseiKakuGo-W5"))
    pdfmetrics.registerFont(UnicodeCIDFont("HeiseiMin-W3"))


def header(c: canvas.Canvas, doc_title: str, font: str, page: int, total: int):
    c.setFillColor(BLUE)
    c.rect(0, H - 52, W, 52, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont(font, 13)
    c.drawString(32, H - 35, doc_title)
    c.setFont("Helvetica", 9)
    c.drawRightString(W - 32, H - 35, f"{page} / {total}")


def footer(c: canvas.Canvas, note: str = ""):
    c.setFillColor(GRAY)
    c.setFont("Helvetica", 8)
    if note:
        c.drawString(32, 18, note)
    c.drawRightString(W - 32, 18, "Sample Document")


def section_bar(c: canvas.Canvas, y: float, text: str, font: str):
    c.setFillColor(LBLUE)
    c.rect(32, y - 6, W - 64, 28, fill=1, stroke=0)
    c.setFillColor(BLUE)
    c.setFont(font, 13)
    c.drawString(42, y, text)


def body_text(c: canvas.Canvas, y: float, text: str, font: str, size: int = 10):
    c.setFillColor(black)
    c.setFont(font, size)
    c.drawString(48, y, text)
    return y - (size + 5)


# ─── DX入門ガイド（日本語・8 ページ・内部リンク付き） ───────────────────────

CHAPTERS_JP = [
    ("第1章　DXとは何か",           3),
    ("第2章　DX推進の現状",         4),
    ("第3章　DX戦略の立案",         5),
    ("第4章　テクノロジーの活用",   6),
    ("第5章　人材・組織の変革",     7),
    ("第6章　まとめと次のステップ", 8),
]

BODY_JP = [
    # (chapter_title, body_lines)
    ("第1章　DXとは何か", [
        "DX（デジタルトランスフォーメーション）とは、デジタル技術を活用して",
        "企業の事業モデル・業務プロセス・組織文化を根本から変革することです。",
        "",
        "単なるデジタル化（デジタイゼーション）とは異なり、DXは顧客価値の創出と",
        "競争優位の確立を目的とした経営戦略として位置付けられます。",
        "",
        "【DX の 3 つの段階】",
        "  1. デジタイゼーション：アナログ情報のデジタル変換",
        "  2. デジタライゼーション：業務プロセスのデジタル化",
        "  3. デジタルトランスフォーメーション：ビジネスモデルの変革",
    ]),
    ("第2章　DX推進の現状", [
        "経済産業省の調査によると、DXに取り組む企業は年々増加していますが、",
        "本格的な変革を実現できている企業はまだ少数にとどまっています。",
        "",
        "【主要な課題】",
        "  ・ 人材不足（デジタル人材の獲得・育成）",
        "  ・ レガシーシステムの刷新コスト",
        "  ・ 組織文化の変革抵抗",
        "  ・ 経営層のデジタルリテラシー不足",
    ]),
    ("第3章　DX戦略の立案", [
        "DX戦略を立案する際は、以下のフレームワークを活用します。",
        "",
        "【DX戦略立案の 5 ステップ】",
        "  Step 1：現状のデジタル成熟度評価",
        "  Step 2：ビジョン・目標の設定",
        "  Step 3：ロードマップの策定",
        "  Step 4：実行体制の構築",
        "  Step 5：KPI 設定とモニタリング",
        "",
        "経営トップのコミットメントが成功の最重要要因です。",
    ]),
    ("第4章　テクノロジーの活用", [
        "DX を推進する主要テクノロジー：",
        "",
        "  ・ クラウドコンピューティング：スケーラブルなインフラ基盤",
        "  ・ AI / 機械学習：業務自動化・意思決定支援",
        "  ・ IoT：リアルタイムデータ収集と活用",
        "  ・ ビッグデータ分析：顧客インサイトの抽出",
        "  ・ ローコード / ノーコード：現場主導のアプリ開発",
        "",
        "技術選定は目的から逆算して行うことが重要です。",
    ]),
    ("第5章　人材・組織の変革", [
        "テクノロジーと同様に、人材と組織文化の変革が DX 成功の鍵です。",
        "",
        "【必要な人材像】",
        "  ・ DX リーダー（経営×デジタル両軸の知見を持つ）",
        "  ・ データサイエンティスト",
        "  ・ UX / CX デザイナー",
        "  ・ アジャイル開発エンジニア",
        "",
        "社内育成と外部採用を組み合わせた人材戦略が有効です。",
    ]),
    ("第6章　まとめと次のステップ", [
        "DX は一度完了するゴールではなく、継続的な変革プロセスです。",
        "",
        "【アクションチェックリスト】",
        "  ☑ 経営層の DX コミットメント確認",
        "  ☑ デジタル成熟度アセスメントの実施",
        "  ☑ パイロットプロジェクトの選定と開始",
        "  ☑ デジタル人材育成計画の策定",
        "  ☑ KPI・モニタリング体制の整備",
        "",
        "まずは小さく始めて、成果を見せながら全社展開を目指しましょう。",
    ]),
]


def generate_dx_guide_jp(path: str):
    font_b = "HeiseiKakuGo-W5"
    font   = "HeiseiMin-W3"
    total  = 8
    title  = "DX入門ガイド"

    c = canvas.Canvas(path, pagesize=A4)
    c.setTitle(title)
    c.setAuthor("Sample")

    # ── Page 1: 表紙 ──────────────────────────────────────────────────────────
    c.bookmarkPage("cover")
    c.setFillColor(BLUE)
    c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont(font_b, 32)
    c.drawCentredString(W / 2, H / 2 + 40, title)
    c.setFont(font, 14)
    c.drawCentredString(W / 2, H / 2, "デジタルトランスフォーメーションの基礎から実践まで")
    c.setFont("Helvetica", 10)
    c.setFillColor(LBLUE)
    c.drawCentredString(W / 2, H / 2 - 40, "8 pages  |  Internal Links  |  TOC")
    c.showPage()

    # ── Page 2: 目次 ─────────────────────────────────────────────────────────
    c.bookmarkPage("toc")
    c.addOutlineEntry("目次", "toc", level=0)
    header(c, title, font_b, 2, total)
    footer(c)

    c.setFillColor(BLUE)
    c.setFont(font_b, 18)
    c.drawString(40, H - 90, "目次")

    c.setStrokeColor(BLUE)
    c.line(40, H - 98, W - 40, H - 98)

    toc_y = H - 130
    for ch_title, pg in CHAPTERS_JP:
        key = f"ch{pg}"
        # 点線
        c.setStrokeColor(GRAY)
        c.setDash(1, 3)
        c.line(48, toc_y - 2, W - 90, toc_y - 2)
        c.setDash()
        # リンクテキスト（章タイトル）
        c.setFillColor(LINK_COLOR)
        c.setFont(font, 12)
        c.drawString(48, toc_y, ch_title)
        # ページ番号
        c.setFillColor(black)
        c.setFont("Helvetica", 11)
        c.drawRightString(W - 48, toc_y, str(pg))
        # クリック可能なリンク領域
        c.linkAbsolute("", key, Rect=(48, toc_y - 4, W - 48, toc_y + 14))
        toc_y -= 36

    c.showPage()

    links_dx_jp = [
        ("経済産業省 DX推進ガイドライン", "https://www.meti.go.jp/policy/it_policy/dx/dx.html"),
        ("IPA DX推進指標",               "https://www.ipa.go.jp/digital/dx/"),
        ("DX白書 2023",                  "https://www.ipa.go.jp/publish/wp-dx/"),
    ]

    # ── Pages 3-8: 各章 ───────────────────────────────────────────────────────
    for i, (ch_title, lines) in enumerate(BODY_JP):
        pg = i + 3
        key = f"ch{pg}"
        c.bookmarkPage(key)
        c.addOutlineEntry(ch_title, key, level=0)

        header(c, title, font_b, pg, total)
        footer(c, "← 目次へ戻る（タップ）")

        section_bar(c, H - 90, ch_title, font_b)

        y = H - 140
        for line in lines:
            c.setFillColor(black)
            c.setFont(font, 10)
            c.drawString(48, y, line)
            y -= 18

        # 最終ページ: 参考リンクセクションを追加
        if pg == total:
            y -= 16
            c.setFillColor(LBLUE)
            c.rect(32, y - 6, W - 64, 24, fill=1, stroke=0)
            c.setFillColor(BLUE)
            c.setFont(font_b, 11)
            c.drawString(42, y, "参考リンク")
            y -= 30
            for link_text, url in links_dx_jp:
                c.setFillColor(LINK_COLOR)
                c.setFont(font, 10)
                c.drawString(60, y, f"・ {link_text}")
                c.setFillColor(GRAY)
                c.setFont("Helvetica", 8)
                c.drawString(72, y - 12, url)
                c.linkURL(url, (60, y - 15, W - 48, y + 10))
                y -= 36

        # 目次へ戻る内部リンク（フッター上に配置）
        c.linkAbsolute("目次へ戻る", "toc", Rect=(32, 10, 180, 30))

        # 前後ページリンク（右下）
        if pg < total:
            next_key = f"ch{pg + 1}"
            c.setFillColor(LINK_COLOR)
            c.setFont(font, 9)
            c.drawRightString(W - 32, 10, "次のページ →")
            c.linkAbsolute("", next_key, Rect=(W - 120, 6, W - 32, 26))

        c.showPage()

    c.save()
    print(f"  [生成] {os.path.basename(path)}  ({total} pages, 内部リンク・外部リンク付き)")


# ─── AI技術と社会の未来（日本語・9 ページ・外部リンク付き） ─────────────────

CHAPTERS_AI_JP = [
    ("第1章　生成AIの最新動向",   3),
    ("第2章　産業への影響",       4),
    ("第3章　倫理と規制",         5),
    ("第4章　労働市場への影響",   6),
    ("第5章　AI活用事例",         7),
    ("第6章　今後の展望",         8),
    ("参考資料・外部リンク",      9),
]

BODY_AI_JP = [
    ("第1章　生成AIの最新動向", [
        "2022年末の ChatGPT 公開以降、生成AIは急速に普及しました。",
        "",
        "【主要な生成AIモデル】",
        "  ・ 大規模言語モデル（LLM）：テキスト生成・要約・翻訳",
        "  ・ 画像生成AI：Stable Diffusion, DALL-E, Midjourney",
        "  ・ マルチモーダルAI：テキスト・画像・音声を横断",
        "",
        "技術の進化スピードは過去のIT革命と比較しても格段に速く、",
        "産業・社会・個人のすべてに影響を及ぼしています。",
    ]),
    ("第2章　産業への影響", [
        "AIは多くの産業で業務変革をもたらしています。",
        "",
        "【産業別インパクト】",
        "  ・ 製造業：予知保全・品質検査の自動化",
        "  ・ 金融：不正検知・投資判断支援",
        "  ・ 医療：画像診断・創薬研究の加速",
        "  ・ 小売：需要予測・パーソナライズ推薦",
        "  ・ 法律：契約書レビュー・判例検索",
    ]),
    ("第3章　倫理と規制", [
        "AIの急速な普及に伴い、倫理・規制面の課題も顕在化しています。",
        "",
        "【主要な規制動向】",
        "  ・ EU AI法（2024年施行）：リスクベースのAI規制",
        "  ・ 米国大統領令（2023年）：AI安全性・セキュリティ基準",
        "  ・ 日本：AI戦略会議・G7広島AIプロセス",
        "",
        "企業は自主的なAI倫理ガイドラインの策定が求められています。",
    ]),
    ("第4章　労働市場への影響", [
        "AIによる自動化は、労働市場に大きな変化をもたらします。",
        "",
        "【影響を受けやすい職種】",
        "  ・ データ入力・処理業務",
        "  ・ 定型的な文書作成",
        "  ・ 基本的なカスタマーサポート",
        "",
        "【新たに需要が高まるスキル】",
        "  ・ AIプロンプトエンジニアリング",
        "  ・ AIツールと協働する能力",
        "  ・ 批判的思考・創造性",
    ]),
    ("第5章　AI活用事例", [
        "【国内先進事例】",
        "",
        "  ▶ 製造業 A 社",
        "     生産ラインの異常検知にAIを導入し、不良品率を 40% 削減",
        "",
        "  ▶ 金融機関 B 社",
        "     LLM を活用した投資レポート自動生成で作業時間を 70% 短縮",
        "",
        "  ▶ 医療機関 C 院",
        "     AI 画像診断支援で早期発見率が 15% 向上",
    ]),
    ("第6章　今後の展望", [
        "AIは今後さらに進化し、社会のあり方を根本から変えていくでしょう。",
        "",
        "【2025-2030 年の展望】",
        "  ・ AGI（汎用人工知能）に向けた研究加速",
        "  ・ エッジAI：端末上でのリアルタイム処理の普及",
        "  ・ AI規制の国際標準化",
        "  ・ 人間とAIの協働モデルの確立",
        "",
        "変化に適応し、AIを戦略的に活用できる組織が競争優位を持ちます。",
    ]),
    ("参考資料・外部リンク", []),  # 外部リンクは別途描画
]

EXTERNAL_LINKS_JP = [
    ("経済産業省 DXレポート",          "https://www.meti.go.jp/shingikai/mono_info_service/digital_transformation/"),
    ("総務省 AI 白書",                 "https://www.soumu.go.jp/"),
    ("EU AI Act 公式サイト",           "https://artificialintelligenceact.eu/"),
    ("OpenAI Research",               "https://openai.com/research"),
    ("Google DeepMind",               "https://deepmind.google/"),
]


def generate_ai_society_jp(path: str):
    font_b = "HeiseiKakuGo-W5"
    font   = "HeiseiMin-W3"
    total  = 9
    title  = "AI技術と社会の未来 2024年版"

    c = canvas.Canvas(path, pagesize=A4)
    c.setTitle(title)

    # ── Page 1: 表紙 ──────────────────────────────────────────────────────────
    c.bookmarkPage("cover")
    c.setFillColor(HexColor("#0d2137"))
    c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont(font_b, 26)
    c.drawCentredString(W / 2, H / 2 + 50, "AI技術と社会の未来")
    c.setFont(font_b, 18)
    c.setFillColor(HexColor("#7ec8e3"))
    c.drawCentredString(W / 2, H / 2 + 10, "2024年版")
    c.setFont(font, 12)
    c.setFillColor(HexColor("#aaaaaa"))
    c.drawCentredString(W / 2, H / 2 - 30, "生成AI・産業影響・倫理規制・今後の展望")
    c.showPage()

    # ── Page 2: 目次 ─────────────────────────────────────────────────────────
    c.bookmarkPage("toc")
    c.addOutlineEntry("目次", "toc", level=0)
    header(c, title, font_b, 2, total)
    footer(c)

    c.setFillColor(BLUE)
    c.setFont(font_b, 18)
    c.drawString(40, H - 90, "目次")
    c.setStrokeColor(BLUE)
    c.line(40, H - 98, W - 40, H - 98)

    toc_y = H - 130
    for ch_title, pg in CHAPTERS_AI_JP:
        key = f"aich{pg}"
        c.setStrokeColor(GRAY)
        c.setDash(1, 3)
        c.line(48, toc_y - 2, W - 90, toc_y - 2)
        c.setDash()
        c.setFillColor(LINK_COLOR)
        c.setFont(font, 12)
        c.drawString(48, toc_y, ch_title)
        c.setFillColor(black)
        c.setFont("Helvetica", 11)
        c.drawRightString(W - 48, toc_y, str(pg))
        c.linkAbsolute("", key, Rect=(48, toc_y - 4, W - 48, toc_y + 14))
        toc_y -= 36

    c.showPage()

    # ── Pages 3-8: 各章 ───────────────────────────────────────────────────────
    for i, (ch_title, lines) in enumerate(BODY_AI_JP[:-1]):
        pg = i + 3
        key = f"aich{pg}"
        c.bookmarkPage(key)
        c.addOutlineEntry(ch_title, key, level=0)

        header(c, title, font_b, pg, total)
        footer(c, "← 目次へ戻る（タップ）")
        section_bar(c, H - 90, ch_title, font_b)

        y = H - 140
        for line in lines:
            c.setFillColor(black)
            c.setFont(font, 10)
            c.drawString(48, y, line)
            y -= 18

        c.linkAbsolute("目次へ戻る", "toc", Rect=(32, 10, 180, 30))
        if pg < total - 1:
            next_key = f"aich{pg + 1}"
            c.setFillColor(LINK_COLOR)
            c.drawRightString(W - 32, 10, "次のページ →")
            c.linkAbsolute("", next_key, Rect=(W - 120, 6, W - 32, 26))

        c.showPage()

    # ── Page 9: 参考資料（外部リンク） ────────────────────────────────────────
    key9 = "aich9"
    c.bookmarkPage(key9)
    c.addOutlineEntry("参考資料・外部リンク", key9, level=0)

    header(c, title, font_b, 9, total)
    footer(c, "← 目次へ戻る（タップ）")
    section_bar(c, H - 90, "参考資料・外部リンク", font_b)

    c.setFillColor(black)
    c.setFont(font, 11)
    c.drawString(48, H - 140, "以下のリンクから関連資料をご参照ください。")

    link_y = H - 185
    for link_text, url in EXTERNAL_LINKS_JP:
        c.setFillColor(LINK_COLOR)
        c.setFont(font, 11)
        c.drawString(60, link_y, f"・ {link_text}")
        c.setFillColor(GRAY)
        c.setFont("Helvetica", 8)
        c.drawString(72, link_y - 13, url)
        c.linkURL(url, (60, link_y - 16, W - 48, link_y + 12))
        link_y -= 44

    c.linkAbsolute("目次へ戻る", "toc", Rect=(32, 10, 180, 30))
    c.showPage()
    c.save()
    print(f"  [生成] {os.path.basename(path)}  ({total} pages, 外部リンク付き)")


# ─── DX Beginner's Guide（英語・8 ページ・内部リンク付き） ──────────────────

CHAPTERS_EN = [
    ("Chapter 1: What is DX?",              3),
    ("Chapter 2: Current State of DX",      4),
    ("Chapter 3: DX Strategy Planning",     5),
    ("Chapter 4: Technology Utilization",   6),
    ("Chapter 5: People & Organization",    7),
    ("Chapter 6: Summary & Next Steps",     8),
]

BODY_EN = [
    ("Chapter 1: What is DX?", [
        "Digital Transformation (DX) refers to the use of digital technologies",
        "to fundamentally change how businesses operate and deliver value.",
        "",
        "Unlike simple digitization, DX is a strategic business initiative",
        "aimed at creating competitive advantage and new customer value.",
        "",
        "The Three Stages of DX:",
        "  1. Digitization  — Converting analog info to digital format",
        "  2. Digitalization — Automating business processes with digital tools",
        "  3. Transformation — Reinventing the business model entirely",
    ]),
    ("Chapter 2: Current State of DX", [
        "Enterprises worldwide are accelerating DX initiatives,",
        "yet full-scale transformation remains challenging for many.",
        "",
        "Key Barriers to DX:",
        "  - Talent shortage (digital skills gap)",
        "  - Legacy system modernization costs",
        "  - Organizational resistance to change",
        "  - Lack of digital literacy among leadership",
        "",
        "Only ~30% of DX initiatives meet their original objectives.",
    ]),
    ("Chapter 3: DX Strategy Planning", [
        "A structured approach to DX strategy is essential for success.",
        "",
        "5-Step DX Strategy Framework:",
        "  Step 1: Assess current digital maturity",
        "  Step 2: Define vision and goals",
        "  Step 3: Build a prioritized roadmap",
        "  Step 4: Establish governance and execution team",
        "  Step 5: Set KPIs and monitoring cadence",
        "",
        "Executive sponsorship is the single most critical success factor.",
    ]),
    ("Chapter 4: Technology Utilization", [
        "Key technologies driving DX initiatives:",
        "",
        "  - Cloud Computing   : Scalable, flexible infrastructure",
        "  - AI / ML           : Automation and decision support",
        "  - IoT               : Real-time data from physical assets",
        "  - Big Data Analytics: Customer insight extraction",
        "  - Low-Code / No-Code: Citizen developer empowerment",
        "",
        "Technology selection must be driven by business objectives, not trends.",
    ]),
    ("Chapter 5: People & Organization", [
        "Technology alone cannot deliver DX — people and culture are essential.",
        "",
        "Critical Talent Profiles:",
        "  - DX Leader          : Business + digital strategy expertise",
        "  - Data Scientist     : Advanced analytics and ML",
        "  - UX / CX Designer   : Human-centered design",
        "  - Agile Engineer     : Iterative development mindset",
        "",
        "A blended strategy of internal upskilling and external hiring is key.",
    ]),
    ("Chapter 6: Summary & Next Steps", [
        "DX is an ongoing journey, not a one-time project.",
        "",
        "Action Checklist:",
        "  [x] Secure executive commitment to DX",
        "  [x] Conduct digital maturity assessment",
        "  [x] Select and launch pilot projects",
        "  [x] Build a digital talent development plan",
        "  [x] Establish KPIs and monitoring systems",
        "",
        "Start small, demonstrate value, and scale what works.",
    ]),
]


def generate_dx_guide_en(path: str):
    total = 8
    title = "DX Beginner's Guide"
    c = canvas.Canvas(path, pagesize=A4)
    c.setTitle(title)

    # Cover
    c.bookmarkPage("cover")
    c.setFillColor(BLUE)
    c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 34)
    c.drawCentredString(W / 2, H / 2 + 40, "DX Beginner's Guide")
    c.setFont("Helvetica", 14)
    c.drawCentredString(W / 2, H / 2, "From Basics to Practice")
    c.setFillColor(LBLUE)
    c.setFont("Helvetica", 10)
    c.drawCentredString(W / 2, H / 2 - 36, "8 pages  |  Internal Links  |  TOC")
    c.showPage()

    # TOC
    c.bookmarkPage("toc_en")
    c.addOutlineEntry("Table of Contents", "toc_en", level=0)
    c.setFillColor(BLUE)
    c.rect(0, H - 52, W, 52, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 13)
    c.drawString(32, H - 35, title)
    c.setFont("Helvetica", 9)
    c.drawRightString(W - 32, H - 35, f"2 / {total}")
    footer(c)

    c.setFillColor(BLUE)
    c.setFont("Helvetica-Bold", 18)
    c.drawString(40, H - 90, "Table of Contents")
    c.setStrokeColor(BLUE)
    c.line(40, H - 98, W - 40, H - 98)

    toc_y = H - 130
    for ch_title, pg in CHAPTERS_EN:
        key = f"ench{pg}"
        c.setStrokeColor(GRAY)
        c.setDash(1, 3)
        c.line(48, toc_y - 2, W - 90, toc_y - 2)
        c.setDash()
        c.setFillColor(LINK_COLOR)
        c.setFont("Helvetica", 12)
        c.drawString(48, toc_y, ch_title)
        c.setFillColor(black)
        c.setFont("Helvetica", 11)
        c.drawRightString(W - 48, toc_y, str(pg))
        c.linkAbsolute("", key, Rect=(48, toc_y - 4, W - 48, toc_y + 14))
        toc_y -= 36
    c.showPage()

    links_dx_en = [
        ("McKinsey on Digital Transformation", "https://www.mckinsey.com/capabilities/mckinsey-digital/"),
        ("MIT Sloan Management Review",         "https://sloanreview.mit.edu/tag/digital-transformation/"),
        ("Gartner Digital Business",            "https://www.gartner.com/en/information-technology/insights/digitalization"),
    ]

    # Chapters
    for i, (ch_title, lines) in enumerate(BODY_EN):
        pg = i + 3
        key = f"ench{pg}"
        c.bookmarkPage(key)
        c.addOutlineEntry(ch_title, key, level=0)

        c.setFillColor(BLUE)
        c.rect(0, H - 52, W, 52, fill=1, stroke=0)
        c.setFillColor(white)
        c.setFont("Helvetica-Bold", 13)
        c.drawString(32, H - 35, title)
        c.setFont("Helvetica", 9)
        c.drawRightString(W - 32, H - 35, f"{pg} / {total}")
        footer(c, "<- Back to TOC (tap)")

        c.setFillColor(LBLUE)
        c.rect(32, H - 102, W - 64, 28, fill=1, stroke=0)
        c.setFillColor(BLUE)
        c.setFont("Helvetica-Bold", 13)
        c.drawString(42, H - 90, ch_title)

        y = H - 140
        for line in lines:
            c.setFillColor(black)
            c.setFont("Helvetica", 10)
            c.drawString(48, y, line)
            y -= 18

        # Last page: add reference links section
        if pg == total:
            y -= 16
            c.setFillColor(LBLUE)
            c.rect(32, y - 6, W - 64, 24, fill=1, stroke=0)
            c.setFillColor(BLUE)
            c.setFont("Helvetica-Bold", 11)
            c.drawString(42, y, "Reference Links")
            y -= 30
            for link_text, url in links_dx_en:
                c.setFillColor(LINK_COLOR)
                c.setFont("Helvetica", 10)
                c.drawString(60, y, f"- {link_text}")
                c.setFillColor(GRAY)
                c.setFont("Helvetica", 8)
                c.drawString(72, y - 12, url)
                c.linkURL(url, (60, y - 15, W - 48, y + 10))
                y -= 36

        c.linkAbsolute("TOC", "toc_en", Rect=(32, 10, 160, 30))
        if pg < total:
            c.setFillColor(LINK_COLOR)
            c.setFont("Helvetica", 9)
            c.drawRightString(W - 32, 10, "Next page ->")
            c.linkAbsolute("", f"ench{pg+1}", Rect=(W - 110, 6, W - 32, 26))
        c.showPage()

    c.save()
    print(f"  [生成] {os.path.basename(path)}  ({total} pages, internal + external links)")


# ─── AI Technology and Society（英語・7 ページ・外部リンク付き） ──────────────

CHAPTERS_AI_EN = [
    ("Chapter 1: Generative AI Trends",   3),
    ("Chapter 2: Industry Impact",         4),
    ("Chapter 3: Ethics & Regulation",     5),
    ("Chapter 4: Future Outlook",          6),
    ("References & External Links",        7),
]

BODY_AI_EN = [
    ("Chapter 1: Generative AI Trends", [
        "The release of ChatGPT in late 2022 triggered rapid mainstream adoption",
        "of generative AI across industries worldwide.",
        "",
        "Key Generative AI Categories:",
        "  - Large Language Models (LLMs): Text generation, summarization",
        "  - Image Generation: Stable Diffusion, DALL-E, Midjourney",
        "  - Multimodal AI: Cross-modal text, image, and audio processing",
        "",
        "The pace of development far exceeds previous technological revolutions.",
    ]),
    ("Chapter 2: Industry Impact", [
        "AI is driving transformative change across all major industries.",
        "",
        "Sector-by-Sector Impact:",
        "  - Manufacturing : Predictive maintenance, quality inspection AI",
        "  - Finance        : Fraud detection, investment analysis",
        "  - Healthcare     : Medical imaging, drug discovery acceleration",
        "  - Retail         : Demand forecasting, personalized recommendations",
        "  - Legal          : Contract review, case law research",
    ]),
    ("Chapter 3: Ethics & Regulation", [
        "Rapid AI adoption has surfaced significant ethical and regulatory questions.",
        "",
        "Key Regulatory Developments:",
        "  - EU AI Act (2024): Risk-based AI regulation framework",
        "  - US Executive Order (2023): AI safety and security standards",
        "  - G7 Hiroshima AI Process: International voluntary code of conduct",
        "",
        "Organizations should proactively develop internal AI ethics guidelines.",
    ]),
    ("Chapter 4: Future Outlook", [
        "AI will continue to reshape society in profound ways through 2030 and beyond.",
        "",
        "Key Trends to Watch (2025-2030):",
        "  - Progress toward Artificial General Intelligence (AGI)",
        "  - Edge AI: Real-time on-device processing at scale",
        "  - International regulatory harmonization",
        "  - Established human-AI collaboration models",
        "",
        "Organizations that adapt strategically will capture competitive advantage.",
    ]),
]

EXTERNAL_LINKS_EN = [
    ("OpenAI Research Blog",             "https://openai.com/research"),
    ("Google DeepMind Publications",     "https://deepmind.google/research/"),
    ("EU Artificial Intelligence Act",   "https://artificialintelligenceact.eu/"),
    ("Stanford AI Index Report",         "https://aiindex.stanford.edu/"),
    ("MIT Technology Review - AI",       "https://www.technologyreview.com/topic/artificial-intelligence/"),
]


def generate_ai_society_en(path: str):
    total = 7
    title = "AI Technology and Society 2024"
    c = canvas.Canvas(path, pagesize=A4)
    c.setTitle(title)

    # Cover
    c.bookmarkPage("cover")
    c.setFillColor(HexColor("#0d2137"))
    c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 28)
    c.drawCentredString(W / 2, H / 2 + 50, "AI Technology and Society")
    c.setFont("Helvetica-Bold", 18)
    c.setFillColor(HexColor("#7ec8e3"))
    c.drawCentredString(W / 2, H / 2 + 10, "2024 Edition")
    c.setFont("Helvetica", 11)
    c.setFillColor(HexColor("#aaaaaa"))
    c.drawCentredString(W / 2, H / 2 - 28, "Generative AI | Industry Impact | Ethics | Future Outlook")
    c.showPage()

    # TOC
    c.bookmarkPage("toc_ai_en")
    c.addOutlineEntry("Table of Contents", "toc_ai_en", level=0)
    c.setFillColor(HexColor("#0d2137"))
    c.rect(0, H - 52, W, 52, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 12)
    c.drawString(32, H - 35, title)
    c.setFont("Helvetica", 9)
    c.drawRightString(W - 32, H - 35, f"2 / {total}")
    footer(c)

    c.setFillColor(HexColor("#0d2137"))
    c.setFont("Helvetica-Bold", 18)
    c.drawString(40, H - 90, "Table of Contents")
    c.setStrokeColor(HexColor("#0d2137"))
    c.line(40, H - 98, W - 40, H - 98)

    toc_y = H - 130
    for ch_title, pg in CHAPTERS_AI_EN:
        key = f"ai_en_ch{pg}"
        c.setStrokeColor(GRAY)
        c.setDash(1, 3)
        c.line(48, toc_y - 2, W - 90, toc_y - 2)
        c.setDash()
        c.setFillColor(LINK_COLOR)
        c.setFont("Helvetica", 12)
        c.drawString(48, toc_y, ch_title)
        c.setFillColor(black)
        c.setFont("Helvetica", 11)
        c.drawRightString(W - 48, toc_y, str(pg))
        c.linkAbsolute("", key, Rect=(48, toc_y - 4, W - 48, toc_y + 14))
        toc_y -= 36
    c.showPage()

    accent = HexColor("#0d2137")

    # Chapters 3-6
    for i, (ch_title, lines) in enumerate(BODY_AI_EN):
        pg = i + 3
        key = f"ai_en_ch{pg}"
        c.bookmarkPage(key)
        c.addOutlineEntry(ch_title, key, level=0)

        c.setFillColor(accent)
        c.rect(0, H - 52, W, 52, fill=1, stroke=0)
        c.setFillColor(white)
        c.setFont("Helvetica-Bold", 12)
        c.drawString(32, H - 35, title)
        c.setFont("Helvetica", 9)
        c.drawRightString(W - 32, H - 35, f"{pg} / {total}")
        footer(c, "<- Back to TOC (tap)")

        c.setFillColor(HexColor("#d0e4f7"))
        c.rect(32, H - 102, W - 64, 28, fill=1, stroke=0)
        c.setFillColor(accent)
        c.setFont("Helvetica-Bold", 13)
        c.drawString(42, H - 90, ch_title)

        y = H - 140
        for line in lines:
            c.setFillColor(black)
            c.setFont("Helvetica", 10)
            c.drawString(48, y, line)
            y -= 18

        c.linkAbsolute("TOC", "toc_ai_en", Rect=(32, 10, 160, 30))
        if pg < total - 1:
            c.setFillColor(LINK_COLOR)
            c.setFont("Helvetica", 9)
            c.drawRightString(W - 32, 10, "Next page ->")
            c.linkAbsolute("", f"ai_en_ch{pg+1}", Rect=(W - 110, 6, W - 32, 26))
        c.showPage()

    # Page 7: References (external links)
    key7 = "ai_en_ch7"
    c.bookmarkPage(key7)
    c.addOutlineEntry("References & External Links", key7, level=0)

    c.setFillColor(accent)
    c.rect(0, H - 52, W, 52, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 12)
    c.drawString(32, H - 35, title)
    c.setFont("Helvetica", 9)
    c.drawRightString(W - 32, H - 35, f"7 / {total}")
    footer(c, "<- Back to TOC (tap)")

    c.setFillColor(HexColor("#d0e4f7"))
    c.rect(32, H - 102, W - 64, 28, fill=1, stroke=0)
    c.setFillColor(accent)
    c.setFont("Helvetica-Bold", 13)
    c.drawString(42, H - 90, "References & External Links")

    c.setFillColor(black)
    c.setFont("Helvetica", 11)
    c.drawString(48, H - 140, "Tap a link to open in the browser:")

    link_y = H - 185
    for link_text, url in EXTERNAL_LINKS_EN:
        c.setFillColor(LINK_COLOR)
        c.setFont("Helvetica-Bold", 11)
        c.drawString(60, link_y, f"- {link_text}")
        c.setFillColor(GRAY)
        c.setFont("Helvetica", 8)
        c.drawString(72, link_y - 13, url)
        c.linkURL(url, (60, link_y - 16, W - 48, link_y + 12))
        link_y -= 44

    c.linkAbsolute("TOC", "toc_ai_en", Rect=(32, 10, 160, 30))
    c.showPage()
    c.save()
    print(f"  [生成] {os.path.basename(path)}  ({total} pages, external links)")


# ─── エントリーポイント ───────────────────────────────────────────────────────

if __name__ == "__main__":
    register_fonts()
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"PDF を生成中... → {OUTPUT_DIR}\n")
    generate_dx_guide_jp(os.path.join(OUTPUT_DIR, "dx_guide_jp.pdf"))
    generate_ai_society_jp(os.path.join(OUTPUT_DIR, "ai_society_report.pdf"))
    generate_dx_guide_en(os.path.join(OUTPUT_DIR, "dx_guide_en.pdf"))
    generate_ai_society_en(os.path.join(OUTPUT_DIR, "ai_society_en.pdf"))
    print("\n完了。")
