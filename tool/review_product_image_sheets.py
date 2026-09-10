"""Generate labelled contact sheets from the identity audit, without altering assets."""
import json
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
report = json.loads((root / 'outputs/product_image_review/inventory.json').read_text())
assets = report['assets']
mode = sys.argv[1] if len(sys.argv) > 1 else 'all'
if mode == 'flagged':
    assets = [asset for asset in assets if asset['flags']]
if mode == 'candidates':
    assets = [dict(asset, index=f"{asset['index']}-{asset['candidate']}", products=[{'row': row} for row in asset['rows']]) for asset in json.loads((root / 'outputs/product_image_review/candidates/candidates.json').read_text()) if not asset.get('error')]
if mode == 'indices':
    selected = set(int(value) for value in sys.argv[2:])
    assets = [asset for asset in assets if asset['index'] in selected]
if mode == 'sourced':
    assets = [dict(asset, index=asset['key'], products=[{'row': row} for row in asset['rows']]) for asset in json.loads((root / 'outputs/product_image_review/sourced/candidates.json').read_text()) if not asset.get('error')]
    if len(sys.argv) > 2:
        assets = [asset for asset in assets if asset['key'] in sys.argv[2:]]
out = root / 'outputs/product_image_review' / mode
out.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype(str(root / 'assets/fonts/Manrope-Variable.ttf'), 12)
small = ImageFont.truetype(str(root / 'assets/fonts/Manrope-Variable.ttf'), 10)
columns, per_sheet, width, height = 6, 48, 238, 234
for page in range(math.ceil(len(assets) / per_sheet)):
    items = assets[page * per_sheet:(page + 1) * per_sheet]
    sheet = Image.new('RGB', (columns * width, math.ceil(len(items) / columns) * height), '#e8ebed')
    draw = ImageDraw.Draw(sheet)
    for i, asset in enumerate(items):
        x, y = i % columns * width, i // columns * height
        draw.rectangle((x+2, y+2, x+width-2, y+height-2), fill='white')
        with Image.open(root / asset['assetImagePath']) as source:
            rgba = source.convert('RGBA')
            source = Image.new('RGBA', rgba.size, 'white')
            source.alpha_composite(rgba)
            source = source.convert('RGB')
            source.thumbnail((width - 14, 158))
            sheet.paste(source, (x+(width-source.width)//2, y+6+(158-source.height)//2))
        label = f"#{asset['index']} {asset['name']}"
        line, lines = '', []
        for word in label.split():
            if draw.textlength((line+' '+word).strip(), font=font) > width-14:
                lines.append(line)
                line = word
            else:
                line = (line+' '+word).strip()
        lines.append(line)
        for j, text in enumerate(lines[:3]):
            draw.text((x+6, y+167+j*15), text, fill='#1a252d', font=font)
        draw.text((x+6, y+215), 'Rows '+','.join(str(p['row']) for p in asset['products'])[:36], fill='#545f65', font=small)
    filename = out / f'sheet-{page+1:02d}.jpg'
    sheet.save(filename, quality=92)
    print(filename)
