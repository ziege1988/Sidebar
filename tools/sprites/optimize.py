# Verkleinert die Sprite-Bilder (256 Farben mit Transparenz) – ca. 3–4× kleiner, optisch gleich.
#   python3 tools/sprites/optimize.py
import pathlib, sys
from PIL import Image
root = pathlib.Path(__file__).resolve().parents[2] / 'Resources' / 'Sprites'
before = after = 0
for f in sorted(root.glob('*/*.png')):
    before += f.stat().st_size
    im = Image.open(f).convert('RGBA')
    q = im.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    q.save(f, optimize=True)
    after += f.stat().st_size
print(f'{before/1e6:.1f} MB → {after/1e6:.1f} MB')
