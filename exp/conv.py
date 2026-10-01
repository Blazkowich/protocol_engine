import pymupdf
import re
import os


# ----------------------------------------------------------------------
# CSS with fixes for inline code inside table cells.
# The `display:inline-block` + `vertical-align:middle` on the
# span-wrapped code forces litehtml to treat it as a single inline
# box, preventing the line-height miscalculation.
# ----------------------------------------------------------------------
USER_CSS = """
/* ---------- Base ---------- */
body {
    font-family: "Helvetica", "Arial", sans-serif;
    font-size: 10.5pt;
    line-height: 1.65;
    color: #2b2b2b;
    margin: 32px 40px;
}

/* ---------- Headings ---------- */
h1, h2, h3, h4, h5, h6 {
    font-family: "Times New Roman", "Georgia", serif;
    color: #1f3a5f;
    font-weight: bold;
    line-height: 1.25;
}
h1 { font-size: 26pt; margin: 8px 0 18px 0; padding-bottom: 8px;
     border-bottom: 2px solid #1f3a5f; }
h2 { font-size: 18pt; margin: 26px 0 12px 0; padding-bottom: 4px;
     border-bottom: 1px solid #d6dde5; }
h3 { font-size: 13.5pt; margin: 20px 0 8px 0; color: #2a4f80; }
h4 { font-size: 11.5pt; margin: 16px 0 6px 0; color: #2a4f80; }
h5, h6 { font-size: 10.5pt; margin: 14px 0 4px 0; color: #4a4a4a; }

/* ---------- Paragraphs & lists ---------- */
p { margin: 8px 0 12px 0; }
ul, ol { margin: 8px 0 14px 22px; }
li { margin: 4px 0; }

/* ---------- Links ---------- */
a { color: #1f6feb; text-decoration: none; }

/* ---------- Inline code (body text) ---------- */
code {
    font-family: "Consolas", "Menlo", monospace;
    font-size: 9.5pt;
    line-height: 1.4;
    background-color: #f3f5f8;
    color: #b3306e;
    padding: 0 4px;
    border-radius: 3px;
}

/* ---------- Code blocks ---------- */
pre {
    font-family: "Consolas", "Menlo", monospace;
    font-size: 9.5pt;
    background-color: #f6f8fa;
    color: #24292f;
    border: 1px solid #e1e4e8;
    border-left: 4px solid #1f3a5f;
    border-radius: 4px;
    padding: 12px 14px;
    line-height: 1.5;
    margin: 12px 0 16px 0;
}
pre code {
    background: transparent;
    color: inherit;
    padding: 0;
    font-size: 9.5pt;
    line-height: inherit;
}

/* ---------- Blockquotes ---------- */
blockquote {
    border-left: 4px solid #b8c4d4;
    background-color: #f8fafc;
    color: #4a5568;
    margin: 12px 0;
    padding: 8px 16px;
    font-style: italic;
}

/* ---------- Tables ---------- */
table {
    width: 100%;
    border-collapse: collapse;
    margin: 16px 0 22px 0;
    font-size: 10pt;
}
thead { background-color: #1f3a5f; }
th {
    color: #ffffff;
    font-family: "Times New Roman", "Georgia", serif;
    font-weight: bold;
    font-size: 10.5pt;
    text-align: left;
    padding: 10px 12px;
    border: 1px solid #1f3a5f;
}
td {
    padding: 9px 12px;
    border: 1px solid #d6dde5;
    vertical-align: top;
    line-height: 1.5;
}
tbody tr:nth-child(even) { background-color: #f6f8fa; }
tbody tr:nth-child(odd)  { background-color: #ffffff; }

/* Keep short cells (like Type) on a single line */
td:nth-child(2), th:nth-child(2) {
    white-space: nowrap;
}

/* ---------- Inline code inside table cells ----------
   Wrapped in <span class="tbl-code"> by the preprocessor.
   display:inline-block + vertical-align:middle prevents the
   line-height miscalculation that causes jagged spacing.
------------------------------------------------ */
span.tbl-code {
    display: inline-block;
    vertical-align: middle;
    font-family: "Consolas", "Menlo", monospace;
    font-size: 9.5pt;
    line-height: 1.4;
    background: transparent;
    color: #b3306e;
    padding: 0;
    border: none;
    border-radius: 0;
}
span.tbl-code code {
    font-family: inherit;
    font-size: inherit;
    line-height: inherit;
    background: transparent;
    color: inherit;
    padding: 0;
    border: none;
    border-radius: 0;
}

/* ---------- Horizontal rule ---------- */
hr { border: none; border-top: 1px solid #d6dde5; margin: 24px 0; }

/* ---------- Images ---------- */
img { margin: 12px 0; border: 1px solid #e1e4e8; border-radius: 4px; }
"""


def convert_svg_to_png(svg_path, png_path, dpi=300):
    """Rasterize an SVG to PNG using PyMuPDF."""
    doc = pymupdf.open(svg_path)
    page = doc[0]
    zoom = dpi / 72.0
    mat = pymupdf.Matrix(zoom, zoom)
    pix = page.get_pixmap(matrix=mat, alpha=False)
    pix.save(png_path)
    doc.close()


def fix_table_inline_code(md_content):
    """
    Wrap inline code inside table cells with a styled span.

    litehtml mis-renders bare <code> elements inside table cells:
    their line-height is not inherited correctly, causing jagged,
    uneven line spacing within the row. Wrapping them in a
    <span class="tbl-code"> with display:inline-block works around
    this rendering bug.
    """
    lines = md_content.split('\n')
    result = []
    in_table = False

    for line in lines:
        stripped = line.strip()

        # Detect table boundaries (Markdown tables use | as column separator)
        if '|' in stripped and stripped.startswith('|'):
            in_table = True
        elif in_table and not stripped.startswith('|'):
            in_table = False

        if in_table and '`' in line:
            # Replace `code` with <span class="tbl-code"><code>code</code></span>
            # but only inside table rows, and only for inline code
            # (backtick pairs, not triple-backtick fences)
            def wrap_code(match):
                return f'<span class="tbl-code"><code>{match.group(1)}</code></span>'

            line = re.sub(r'`([^`]+)`', wrap_code, line)

        result.append(line)

    return '\n'.join(result)


def preprocess_markdown(md_file):
    """Replace .svg refs with .png refs and fix table inline code."""
    base_dir = os.path.dirname(os.path.abspath(md_file)) or "."
    with open(md_file, "r", encoding="utf-8") as f:
        md_content = f.read()

    # --- Step 1: Convert SVG references to PNG ---
    pattern = r'!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)'
    for match in re.finditer(pattern, md_content):
        full_match = match.group(0)
        alt_text = match.group(1)
        img_path = match.group(2)
        title = match.group(3) if match.group(3) else ""

        if img_path.lower().endswith(".svg"):
            abs_svg = os.path.join(base_dir, img_path)
            if not os.path.isfile(abs_svg):
                print(f"Warning: SVG not found: {abs_svg}")
                continue

            png_name = os.path.splitext(img_path)[0] + ".png"
            abs_png = os.path.join(base_dir, png_name)

            try:
                convert_svg_to_png(abs_svg, abs_png, dpi=300)
                print(f"Converted {img_path} -> {png_name}")
            except Exception as e:
                print(f"Failed to convert {img_path}: {e}")
                continue

            new_ref = f'![{alt_text}]({png_name}'
            if title:
                new_ref += f' "{title}"'
            new_ref += ')'
            md_content = md_content.replace(full_match, new_ref)

    # --- Step 2: Fix inline code inside table cells ---
    md_content = fix_table_inline_code(md_content)

    processed_md = os.path.splitext(md_file)[0] + "_processed.md"
    with open(processed_md, "w", encoding="utf-8") as f:
        f.write(md_content)

    return processed_md, base_dir


def find_content_bottom(page):
    """Return the lowest y coordinate used by any content on the page."""
    max_y = 0.0

    for block in page.get_text("blocks"):
        max_y = max(max_y, block[3])  # y1

    for d in page.get_drawings():
        r = d.get("rect")
        if r:
            max_y = max(max_y, r.y1)

    for img in page.get_image_info():
        bbox = img.get("bbox")
        if bbox:
            max_y = max(max_y, bbox[3])

    return max_y


def md_to_single_long_page_pdf(md_file, output_pdf, page_width=595.0):
    """Convert Markdown to a single long-page PDF (no page breaks)."""
    processed_md, base_dir = preprocess_markdown(md_file)
    archive = pymupdf.Archive(base_dir)

    # Step 1: Render into a very tall temporary page so nothing wraps.
    MAX_H = 14400.0  # PDF practical max page height in points
    tall_rect = pymupdf.Rect(0, 0, page_width, MAX_H)
    md_doc = pymupdf.open(
        processed_md,
        archive=archive,
        rect=tall_rect,
    )

    # Apply the elegant CSS
    md_doc.apply_css(USER_CSS)

    # Convert to real PDF bytes
    pdf_bytes = md_doc.convert_to_pdf()
    md_doc.close()

    tall_pdf = pymupdf.open("pdf", pdf_bytes)

    if tall_pdf.page_count > 1:
        print(f"Note: content spilled onto {tall_pdf.page_count} pages; "
              f"using the first page only. Increase MAX_H if needed.")

    page = tall_pdf[0]

    # Step 2: Measure real content height.
    content_bottom = find_content_bottom(page)
    if content_bottom <= 0:
        content_bottom = 100.0
    new_height = content_bottom + 40.0  # generous bottom margin

    # Step 3: New single-page PDF, copy content at correct height (no scaling).
    new_doc = pymupdf.open()
    new_page = new_doc.new_page(width=page_width, height=new_height)

    # Optional: paint a soft off-white page background for a paper feel
    new_page.draw_rect(
        new_page.rect,
        color=None,
        fill=(0.99, 0.99, 0.985),
        overlay=False,
    )

    new_page.show_pdf_page(
        new_page.rect,
        tall_pdf,
        0,
        clip=pymupdf.Rect(0, 0, page_width, new_height),
    )

    new_doc.save(output_pdf)
    new_doc.close()
    tall_pdf.close()

    print(f"Saved single-page PDF: {output_pdf}  "
          f"({page_width:.0f} x {new_height:.0f} pt)")


if __name__ == "__main__":
    md_to_single_long_page_pdf("protocol_engine.md", "protocol_engine.pdf")