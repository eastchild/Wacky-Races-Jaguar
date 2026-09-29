"""pacing.py F0 F1 : per dump frame (GB-time run): next frame drawn (D) or not (u), streaming (s),
VBlanks late, consecutive skips. Offsets: VARS $1000 (vbl_count $1C, fe_vbl $108, rnd $10C,
skipn $120, strm $121)."""
import sys, struct
f0, f1 = int(sys.argv[1]), int(sys.argv[2])
L = lambda v, o: struct.unpack('>I', v[o:o + 4])[0]
for f in range(f0, f1 + 1):
    try:
        v = open(f'test/out/vars_{f}.bin', 'rb').read()
    except OSError:
        print(f, '-')
        continue
    late = L(v, 0x1c) - L(v, 0x108)
    print(f, ('D' if v[0x10c] else 'u') + ('s' if v[0x121] else ' '), 'late', late, 'skipn', v[0x120])
