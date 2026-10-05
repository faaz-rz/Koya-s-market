"""Create a labelled contact sheet of the actual bundled category pictures.

Run with Python + Pillow. The source of truth remains CategoryTile.imageAssetFor;
this helper never changes source pictures or product/catalogue data.
"""

import json
import math
from pathlib import Path
import re

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "lib/features/products/widgets/category_tile.dart").read_text()
assets = dict(re.findall(r"'([^']+)'\s*=>\s*'(assets/[^']+)'", source))
categories = json.loads((ROOT / "catalogue/categories.json").read_text())
columns, cell_width, cell_height = 5, 240, 205
sheet = Image.new(
    "RGB", (columns * cell_width, math.ceil(len(categories) / columns) * cell_height),
    "#f7f8f2",
)
draw = ImageDraw.Draw(sheet)
font = ImageFont.load_default(size=15)
for index, category in enumerate(categories):
    x, y = (index % columns) * cell_width, (index // columns) * cell_height
    picture = Image.open(ROOT / assets[category["key"]]).convert("RGBA")
    picture.thumbnail((cell_width - 24, cell_height - 42))
    sheet.paste(picture, (x + (cell_width - picture.width) // 2, y + 8), picture)
    draw.text((x + 10, y + cell_height - 27), category["name"], font=font, fill="#23311c")

output = ROOT / "outputs/category_review/all-category-pictures.jpg"
output.parent.mkdir(parents=True, exist_ok=True)
sheet.save(output, quality=94)
print(output)
