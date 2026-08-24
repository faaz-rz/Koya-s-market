import io
import json
import math
import os
import sys
import urllib.request
from urllib.parse import urlparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


WORKSPACE = Path(__file__).resolve().parent.parent
REPORT_PATH = WORKSPACE / "outputs/product_image_import/web_scrape_report.json"
OUTPUT_DIRECTORY = WORKSPACE / "outputs/product_image_import/contact_sheets"
ITEMS_PER_SHEET = 30
CELL_WIDTH = 220
CELL_HEIGHT = 260
IMAGE_SIZE = 188
LABEL_HEIGHT = 58
COLS = 5


def load_font(size: int):
    candidates = [
        WORKSPACE / "assets/fonts/Manrope-Variable.ttf",
        Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def fit_image(image: Image.Image, size: int) -> Image.Image:
    source = image.convert("RGB")
    source.thumbnail((size, size), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (size, size), "white")
    x = (size - source.width) // 2
    y = (size - source.height) // 2
    canvas.paste(source, (x, y))
    return canvas


def wrapped_lines(draw: ImageDraw.ImageDraw, text: str, font, max_width: int):
    words = text.split()
    lines = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if draw.textlength(candidate, font=font) <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines[:2]


def main():
    report_path = REPORT_PATH
    limit = None
    include_rejected = False
    for argument in sys.argv[1:]:
        if argument.startswith("--report="):
            report_path = WORKSPACE / argument.split("=", 1)[1]
        elif argument == "--include-rejected":
            include_rejected = True
        else:
            limit = int(argument)
    report = json.loads(report_path.read_text())
    if include_rejected:
        accepted = [
            item for item in report.get("rejected", []) if item.get("imageUrl")
        ]
    else:
        accepted = [
            item
            for item in report.get("accepted", [])
            if item.get("assetImagePath")
            and (WORKSPACE / item["assetImagePath"]).exists()
        ]
    if limit is not None:
        accepted = accepted[:limit]
    OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    font = load_font(13)
    small_font = load_font(11)
    sheet_count = math.ceil(len(accepted) / ITEMS_PER_SHEET)
    for sheet_index in range(sheet_count):
        page_items = accepted[
            sheet_index * ITEMS_PER_SHEET : (sheet_index + 1) * ITEMS_PER_SHEET
        ]
        rows = math.ceil(len(page_items) / COLS)
        sheet = Image.new(
            "RGB",
            (COLS * CELL_WIDTH, rows * CELL_HEIGHT),
            "#f4f5f7",
        )
        draw = ImageDraw.Draw(sheet)
        for item_index, item in enumerate(page_items):
            row = item_index // COLS
            col = item_index % COLS
            x = col * CELL_WIDTH
            y = row * CELL_HEIGHT
            draw.rounded_rectangle(
                (x + 5, y + 5, x + CELL_WIDTH - 5, y + CELL_HEIGHT - 5),
                radius=12,
                fill="white",
                outline="#d5d9df",
            )
            if item.get("assetImagePath"):
                image_source = WORKSPACE / item["assetImagePath"]
            else:
                request = urllib.request.Request(
                    item["imageUrl"],
                    headers={"User-Agent": "KoyasSupermarket/1.0"},
                )
                try:
                    image_source = io.BytesIO(
                        urllib.request.urlopen(request, timeout=20).read()
                    )
                except Exception:
                    image_source = None
            if image_source is None:
                fitted = Image.new("RGB", (IMAGE_SIZE, IMAGE_SIZE), "#f6d6d6")
                error_draw = ImageDraw.Draw(fitted)
                error_draw.text((12, 82), "IMAGE UNAVAILABLE", fill="#8f1d1d", font=font)
            else:
                with Image.open(image_source) as image:
                    fitted = fit_image(image, IMAGE_SIZE)
            sheet.paste(fitted, (x + (CELL_WIDTH - IMAGE_SIZE) // 2, y + 12))
            source_rows = item.get("rows", [])
            rows_label = ", ".join(str(value) for value in source_rows[:4])
            if len(source_rows) > 4:
                rows_label += f" +{len(source_rows) - 4}"
            label = f"Rows {rows_label} · {item.get('name', '')}"
            text_y = y + IMAGE_SIZE + 18
            for line_index, line in enumerate(
                wrapped_lines(draw, label, font, CELL_WIDTH - 20)
            ):
                draw.text((x + 10, text_y + line_index * 17), line, fill="#17202a", font=font)
            host = item.get("selected", {}).get("sourceHost", "")
            if not host and item.get("sourceUrl"):
                host = urlparse(item["sourceUrl"]).hostname or ""
            if not host and item.get("imageUrl"):
                host = urlparse(item["imageUrl"]).hostname or ""
            draw.text(
                (x + 10, y + CELL_HEIGHT - 24),
                host,
                fill="#68717d",
                font=small_font,
            )
        output_path = OUTPUT_DIRECTORY / f"products-{sheet_index + 1:03d}.jpg"
        sheet.save(output_path, quality=88, optimize=True)
        print(output_path)


if __name__ == "__main__":
    main()
