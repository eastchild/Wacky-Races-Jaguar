"""fbview.py FILE.bin [out.png] : convert a 160x144 RGB16 (Jaguar) framebuffer dump to PNG (x2)"""
import sys
from PIL import Image
d = open(sys.argv[1], 'rb').read()
im = Image.new('RGB', (160, 144))
px = im.load()
for y in range(144):
    for x in range(160):
        v = d[(y * 160 + x) * 2] << 8 | d[(y * 160 + x) * 2 + 1]
        r, b, g = v >> 11, (v >> 6) & 31, v & 63
        px[x, y] = (r * 255 // 31, g * 255 // 63, b * 255 // 31)
im = im.resize((320, 288), Image.NEAREST)
im.save(sys.argv[2] if len(sys.argv) > 2 else sys.argv[1].replace('.bin', '.png'))
