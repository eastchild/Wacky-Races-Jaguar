"""hudpal.py F : race HUD sprites (OAM, top 60 lines) and the GPU OBJ colour table at dump F"""
import sys, struct
f = sys.argv[1]
fl = open(f'test/out/flat_{f}.bin', 'rb').read()
g = open(f'test/out/gpuram_{f}.bin', 'rb').read()
import os
src = int(os.environ.get('OAMSRC', 'FE00'), 16)
oam = fl[src - 0x8000:src - 0x8000 + 160]
pals = {}
for i in range(40):
    y, x, t, a = oam[4 * i:4 * i + 4]
    if 0 < y < 16 + 60 and 0 < x < 168:
        print(f'spr {i:2d} y={y - 16:3d} x={x - 8:3d} tile={t:02x} attr={a:02x} pal={a & 7} bank={a >> 3 & 1}')
        pals[a & 7] = 1
OBC = 0xF039F8 + 160 + 8 + 128 + 8 + 128 + 64 - 0xF03000
for p in sorted(pals):
    cols = [struct.unpack('>I', g[OBC + 16 * p + 4 * c:OBC + 16 * p + 4 * c + 4])[0] for c in range(4)]
    print(f'OBJ pal {p}:', ' '.join(f'{c:04x}' for c in cols), '(rgb565 GPU)')
raw = fl  # 68k raw copy is in VARS; print obpal_raw from vars dump
v = open(f'test/out/vars_{f}.bin', 'rb').read()
obraw = v[0x74:0x74 + 64] if len(v) > 0xb4 else b''
for p in sorted(pals):
    ws = [obraw[8 * p + 2 * c] | obraw[8 * p + 2 * c + 1] << 8 for c in range(4)]
    print(f'obpal_raw {p}:', ' '.join(f'{w:04x}' for w in ws), '(GB)')
