"""fbcmp.py DIR_A DIR_B [sheet.png] : compare the framebuffer dumps fb0_N.bin of two test runs
(test/sync.ps1). Prints the frames that differ (number of differing pixels, first lines) and,
with a third argument, writes a contact sheet A | B | difference of the first ones."""
import sys, os, re

a, b = sys.argv[1], sys.argv[2]
fr = sorted(int(m.group(1)) for m in (re.match(r'fb0_(\d+)\.bin$', f) for f in os.listdir(a)) if m)
bad, miss, blank = [], [], 0
for n in fr:
    pa = open(os.path.join(a, f'fb0_{n}.bin'), 'rb').read()
    try:
        pb = open(os.path.join(b, f'fb0_{n}.bin'), 'rb').read()
    except OSError:
        miss.append(n)
        continue
    if not any(pa):
        blank += 1
    if pa != pb:
        px = [i for i in range(0, len(pa), 2) if pa[i:i + 2] != pb[i:i + 2]]
        lines = sorted({i // 320 for i in px})
        bad.append((n, len(px), lines))
print(f'{len(fr)} frames, {len(bad)} differ, {len(miss)} missing, {blank} blank in A')
for n, c, lines in bad[:40]:
    print(f'  frame {n}: {c} pixels, lines {lines[0]}-{lines[-1]} ({len(lines)})')
if miss:
    print('  missing:', miss[:20])
if len(sys.argv) > 3 and bad:
    from PIL import Image

    def img(d):
        im = Image.new('RGB', (160, 144))
        px = im.load()
        for y in range(144):
            for x in range(160):
                v = d[(y * 160 + x) * 2] << 8 | d[(y * 160 + x) * 2 + 1]
                px[x, y] = ((v >> 11) * 255 // 31, (v & 63) * 255 // 63, ((v >> 6) & 31) * 255 // 31)
        return im
    sel = bad[:8]
    sheet = Image.new('RGB', (480, 144 * len(sel)))
    for k, (n, c, lines) in enumerate(sel):
        pa = open(os.path.join(a, f'fb0_{n}.bin'), 'rb').read()
        pb = open(os.path.join(b, f'fb0_{n}.bin'), 'rb').read()
        ia, ib = img(pa), img(pb)
        df = Image.new('RGB', (160, 144))
        dp = df.load()
        for i in range(0, len(pa), 2):
            if pa[i:i + 2] != pb[i:i + 2]:
                dp[(i // 2) % 160, i // 320] = (255, 0, 0)
        sheet.paste(ia, (0, 144 * k)); sheet.paste(ib, (160, 144 * k)); sheet.paste(df, (320, 144 * k))
    sheet.save(sys.argv[3])
sys.exit(1 if bad or miss else 0)
