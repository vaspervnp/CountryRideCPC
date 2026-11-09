#!/usr/bin/env python3
"""The manuals: docs/manual-en.md and docs/manual-el.md into PDFs beside them.

Reads only what the manuals use of Markdown: headings, paragraphs, bullets,
tables, pictures alone on a line, code fences, **bold** and `code` (set bold).
Needs fpdf2 and Pillow, and the Noto fonts for the Greek. Their pictures are
`make shots`' but for screen-race.png and screen-fork.png, frames of a recorded
race, and sign-curve.png and sign-limit.png, parts of prop-curve.png and
prop-limit.png.
"""

import os
import re
import sys

from fpdf import FPDF
from fpdf.fonts import FontFace
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
FONTS = "/usr/share/fonts/truetype/noto"

NAVY = (0, 0, 128)
RED = (214, 0, 0)
YELLOW = (255, 214, 0)
INK = (34, 34, 44)
HEAD = (232, 232, 244)
RULE = (190, 190, 205)
BOX = (240, 240, 247)
FOOT = (110, 110, 130)

WORDS = {
    "en": dict(contents="Contents", name="Manual"),
    "el": dict(contents="Περιεχόμενα", name="Εγχειρίδιο"),
}
PICTURE = re.compile(r"!\[(.*?)\]\((.*?)\)")
MARGIN = 20
BOTTOM = 20
BODY = 10
LINE = 5.2
PAD = 1.6
PIC_W = 96              # a picture alone on a line
HERO_W = 150
SIGN_W = 30             # a picture in a table's row of text


def blocks(text):
    """The manual's blocks, as (kind, data)."""
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        s = lines[i]
        if not s.strip():
            i += 1
        elif s.startswith("```"):
            j = i + 1
            while not lines[j].startswith("```"):
                j += 1
            out.append(("code", lines[i + 1:j]))
            i = j + 1
        elif s.startswith("#"):
            n = len(s) - len(s.lstrip("#"))
            out.append(("h%d" % n, s[n:].strip()))
            i += 1
        elif s.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-+:?", c) for c in cells):
                    rows.append(cells)
                i += 1
            out.append(("table", rows))
        elif s.startswith("- "):
            items = []
            while i < len(lines) and lines[i].startswith("- "):
                items.append(lines[i][2:].strip())
                i += 1
            out.append(("list", items))
        elif PICTURE.fullmatch(s.strip()):
            out.append(("picture", PICTURE.fullmatch(s.strip()).group(2)))
            i += 1
        else:
            para = []
            while i < len(lines) and lines[i].strip() and lines[i][0] not in "#|`" \
                    and not lines[i].startswith("- ") and not PICTURE.fullmatch(lines[i].strip()):
                para.append(lines[i].strip())
                i += 1
            out.append(("para", " ".join(para)))
    return out


def inline(s):
    """Markdown's spans as fpdf2's: only **bold** is left."""
    return re.sub(r"`(.*?)`", r"**\1**", s)


def plain(s):
    return re.sub(r"\*\*|`", "", s)


def picture_ratio(path):
    with Image.open(os.path.join(DOCS, path)) as im:
        return im.height / im.width


class Manual(FPDF):
    def __init__(self, words):
        super().__init__(format="A4")
        self.words = words
        self.title_text = ""
        self.set_auto_page_break(True, BOTTOM)
        self.set_margins(MARGIN, 18, MARGIN)
        self.add_font("Noto", "", os.path.join(FONTS, "NotoSans-Regular.ttf"))
        self.add_font("Noto", "B", os.path.join(FONTS, "NotoSans-Bold.ttf"))
        self.add_font("Mono", "", os.path.join(FONTS, "NotoSansMono-Regular.ttf"))

    def footer(self):
        self.set_y(-14)
        self.set_font("Noto", "", 8)
        self.set_text_color(*FOOT)
        self.cell(0, 5, "%s, %s" % (self.title_text, self.words["name"]), align="L")
        self.set_x(MARGIN)
        self.cell(0, 5, str(self.page_no()), align="R")

    def usable(self):
        return self.h - BOTTOM - self.t_margin

    def room(self, h):
        """A new page unless h is left on this one - if it fits on one."""
        if h <= self.usable() and self.get_y() + h > self.h - BOTTOM:
            self.add_page()

    def body(self):
        self.set_font("Noto", "", BODY)
        self.set_text_color(*INK)

    # -- how high a block will be -------------------------------------------

    def text_h(self, s, w=0, bold=False):
        self.set_font("Noto", "B" if bold else "", BODY)
        return LINE * len(self.multi_cell(w, LINE, inline(s), markdown=True, dry_run=True, output="LINES"))

    def col_widths(self, rows):
        """Each column as wide as its text asks, none narrower than its longest
        word; pictures beside text a fixed width, a grid of them all alike."""
        n, width = len(rows[0]), self.epw
        if any(PICTURE.fullmatch(c) for r in rows for c in r):
            if any(PICTURE.fullmatch(c) and not all(PICTURE.fullmatch(d) for d in r) for r in rows for c in r):
                return [SIGN_W, width - SIGN_W]
            return [width / n] * n
        extra = 2 * PAD + 1
        want, least = [0] * n, [0] * n
        for j, r in enumerate(rows):
            for k, c in enumerate(r):
                self.set_font("Noto", "B" if j == 0 or c.startswith("**") else "", BODY)
                want[k] = max(want[k], self.get_string_width(plain(c)) + extra)
                for word in plain(c).split():
                    least[k] = max(least[k], self.get_string_width(word) + extra)
        if sum(want) <= width:
            return [w * width / sum(want) for w in want]
        spare, over = width - sum(least), sum(w - m for w, m in zip(want, least))
        return [m + spare * (w - m) / over for w, m in zip(want, least)]

    def table_h(self, rows):
        widths = self.col_widths(rows)
        total = 0
        for j, r in enumerate(rows):
            h = 0
            for w, c in zip(widths, r):
                m = PICTURE.fullmatch(c)
                if m:
                    h = max(h, (w - 2 * PAD) * picture_ratio(m.group(2)))
                elif c:
                    h = max(h, self.text_h(c, w - 2 * PAD, j == 0))
            total += h + 2 * PAD
        return total + 4

    def block_h(self, kind, data):
        """What of a block must be on the page its lead-in is on."""
        if kind == "table":                     # (a long one may go over a page)
            return self.table_h(data[:3] if len(data) > 8 else data)
        if kind == "picture":
            return PIC_W * picture_ratio(data) + 4
        if kind == "code":
            return 5.6 * len(data) + 8
        if kind == "list":
            return sum(self.text_h(s, self.epw - 6) + 1 for s in data[:3]) + 1.5
        if kind == "para":
            return self.text_h(data)
        return 0

    def lead_h(self, parts, i):
        """From block i: its headings and the paragraph that leads into what
        follows, with that - to stay on one page."""
        total = 0
        while i < len(parts):
            kind, data = parts[i]
            if kind == "h2":
                total += 18
            elif kind == "h3":
                total += 10
            elif kind == "para" and data.endswith(":"):
                total += self.text_h(data) + 2.4
            else:
                return total + self.block_h(kind, data)
            i += 1
        return total

    # -- the blocks ---------------------------------------------------------

    def title_page(self, title, subtitle, hero, intro, toc):
        self.title_text = title
        self.add_page()
        self.set_fill_color(*NAVY)
        self.rect(0, 0, self.w, 46, style="F")
        self.set_fill_color(*RED)
        self.rect(0, 46, self.w, 1.6, style="F")
        self.set_xy(MARGIN, 11)
        self.set_font("Noto", "B", 32)
        self.set_text_color(*YELLOW)
        self.cell(0, 14, title.upper())
        self.set_xy(MARGIN, 28)
        self.set_font("Noto", "", 11)
        self.set_text_color(255, 255, 255)
        self.cell(0, 8, subtitle)
        self.set_y(54)
        self.image(os.path.join(DOCS, hero), x=(self.w - HERO_W) / 2, w=HERO_W)
        self.ln(5)
        self.para(intro)
        self.ln(1)
        toc()

    def h2(self, s):
        if self.get_y() > self.t_margin + 1:
            self.ln(5)
        self.start_section(s, level=0)
        self.set_font("Noto", "B", 15)
        self.set_text_color(*NAVY)
        self.multi_cell(0, 8, s, align="L", new_x="LMARGIN", new_y="NEXT")
        y = self.get_y() + 0.6
        self.set_draw_color(*RED)
        self.set_line_width(0.5)
        self.line(MARGIN, y, self.w - MARGIN, y)
        self.ln(3.5)

    def h3(self, s):
        self.ln(2)
        self.set_font("Noto", "B", 11)
        self.set_text_color(*NAVY)
        self.multi_cell(0, 6.5, s, align="L", new_x="LMARGIN", new_y="NEXT")
        self.ln(0.5)

    def para(self, s):
        self.body()
        self.multi_cell(0, LINE, inline(s), markdown=True, align="L", new_x="LMARGIN", new_y="NEXT")
        self.ln(2.4)

    def bullets(self, items):
        for s in items:
            self.room(self.text_h(s, self.epw - 6))
            self.body()
            self.set_x(MARGIN + 1.5)
            self.cell(4.5, LINE, "•")
            self.multi_cell(0, LINE, inline(s), markdown=True, align="L", new_x="LMARGIN", new_y="NEXT")
            self.ln(0.9)
        self.ln(1.5)

    def code(self, lines):
        h = 5.6 * len(lines) + 5
        y = self.get_y()
        self.set_fill_color(*BOX)
        self.rect(MARGIN, y, self.epw, h, style="F")
        self.set_fill_color(*NAVY)
        self.rect(MARGIN, y, 1.2, h, style="F")
        self.set_font("Mono", "", 10.5)
        self.set_text_color(*NAVY)
        self.set_y(y + 2.5)
        for s in lines:
            self.set_x(MARGIN + 5)
            self.cell(0, 5.6, s, new_x="LMARGIN", new_y="NEXT")
        self.set_y(y + h + 3)

    def picture(self, path):
        self.image(os.path.join(DOCS, path), x=(self.w - PIC_W) / 2, w=PIC_W)
        self.ln(3.5)

    def md_table(self, rows):
        widths = self.col_widths(rows)
        grid = len(set(round(w) for w in widths)) == 1 and any(PICTURE.fullmatch(c) for r in rows for c in r)
        self.body()
        self.set_fill_color(255, 255, 255)
        self.set_draw_color(*RULE)
        self.set_line_width(0.2)
        head = FontFace(emphasis="BOLD", color=NAVY, fill_color=HEAD)
        with self.table(col_widths=widths, headings_style=head, line_height=LINE, padding=PAD,
                        text_align="LEFT", markdown=True, borders_layout="HORIZONTAL_LINES",
                        v_align="MIDDLE") as t:
            for cells in rows:
                row = t.row()
                names = grid and not any(PICTURE.fullmatch(c) for c in cells)
                for c in cells:
                    m = PICTURE.fullmatch(c)
                    if m:
                        row.cell(img=os.path.join(DOCS, m.group(2)), img_fill_width=True)
                    else:
                        row.cell(plain(c) if names else inline(c), style=head if names else None)
        self.ln(3.5)


def toc_renderer(pdf):
    def render(_, outline):
        # (at the end of the document, on an earlier page: the colours afresh)
        pdf.set_fill_color(255, 255, 255)
        pdf.set_x(MARGIN)
        pdf.set_font("Noto", "B", 12)
        pdf.set_text_color(*NAVY)
        pdf.cell(0, 8, pdf.words["contents"], new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Noto", "", BODY)
        pdf.set_text_color(*INK)
        for s in outline:
            if s.level:
                continue
            y = pdf.get_y()
            pdf.cell(0, 5.6, s.name, link=pdf.add_link(page=s.page_number))
            pdf.set_xy(MARGIN, y)
            pdf.cell(0, 5.6, str(s.page_number), align="R", new_x="LMARGIN", new_y="NEXT")
    return render


def build(lang):
    words = WORDS[lang]
    with open(os.path.join(DOCS, "manual-%s.md" % lang), encoding="utf-8") as f:
        parts = blocks(f.read())
    assert [k for k, _ in parts[:4]] == ["h1", "para", "picture", "para"]
    pdf = Manual(words)
    title = parts[0][1]
    pdf.set_title("%s, %s" % (title, words["name"]))
    pdf.set_author("Revive8bit, Vasper")
    pdf.set_lang(lang)
    pdf.title_page(title, parts[1][1].strip("*"), parts[2][1], parts[3][1],
                   lambda: pdf.insert_toc_placeholder(toc_renderer(pdf), pages=1))
    parts = parts[4:]
    for i, (kind, data) in enumerate(parts):
        if kind in ("h2", "h3", "para", "list", "table", "picture", "code"):
            pdf.room(pdf.lead_h(parts, i))
        if kind == "h2":
            pdf.h2(data)
        elif kind == "h3":
            pdf.h3(data)
        elif kind == "para":
            pdf.para(data)
        elif kind == "list":
            pdf.bullets(data)
        elif kind == "code":
            pdf.code(data)
        elif kind == "picture":
            pdf.picture(data)
        elif kind == "table":
            pdf.md_table(data)
    out = os.path.join(DOCS, "manual-%s.pdf" % lang)
    pdf.output(out)
    print("wrote %s, %d pages" % (os.path.relpath(out, ROOT), pdf.pages_count))


if __name__ == "__main__":
    for language in sys.argv[1:] or WORDS:
        build(language)
