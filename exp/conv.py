import pymupdf
import re
import os

def convert_svg_to_png(svg_path, png_path, dpi=300):
    """Convert an SVG file to a PNG using PyMuPDF."""
    doc = pymupdf.open(svg_path)
    page = doc[0]
    # PyMuPDF default resolution is 72 DPI; scale to desired DPI
    zoom = dpi / 72.0
    mat = pymupdf.Matrix(zoom, zoom)
    pix = page.get_pixmap(matrix=mat, alpha=False)
    pix.save(png_path)
    doc.close()

def main():
    md_file = "protocol_engine.md"
    output_pdf = "protocol_engine.pdf"
    base_dir = os.path.dirname(os.path.abspath(md_file)) or "."

    # Read the original Markdown
    with open(md_file, "r", encoding="utf-8") as f:
        md_content = f.read()

    # Find all image references: ![alt](path "title")
    pattern = r'!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)'
    matches = list(re.finditer(pattern, md_content))

    for match in matches:
        full_match = match.group(0)
        alt_text = match.group(1)
        img_path = match.group(2)
        title = match.group(3) if match.group(3) else ""

        # Only process SVG files
        if img_path.lower().endswith('.svg'):
            abs_svg = os.path.join(base_dir, img_path)
            if not os.path.isfile(abs_svg):
                print(f"Warning: SVG not found: {abs_svg}")
                continue

            # Build PNG path in the same directory
            png_name = os.path.splitext(img_path)[0] + ".png"
            abs_png = os.path.join(base_dir, png_name)

            try:
                convert_svg_to_png(abs_svg, abs_png, dpi=300)
                print(f"Converted {img_path} -> {png_name}")
            except Exception as e:
                print(f"Failed to convert {img_path}: {e}")
                continue

            # Replace the SVG reference with the PNG reference
            new_ref = f'![{alt_text}]({png_name}'
            if title:
                new_ref += f' "{title}"'
            new_ref += ')'
            md_content = md_content.replace(full_match, new_ref)

    # Write the processed Markdown to a temporary file
    processed_md = os.path.splitext(md_file)[0] + "_processed.md"
    with open(processed_md, "w", encoding="utf-8") as f:
        f.write(md_content)

    # Convert the processed Markdown to PDF, providing the resource archive
    archive = pymupdf.Archive(base_dir)
    md_doc = pymupdf.open(processed_md, archive=archive)
    md_doc.save(output_pdf)
    print(f"PDF saved to {output_pdf}")

if __name__ == "__main__":
    main()