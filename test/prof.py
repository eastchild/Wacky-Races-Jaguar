"""prof.py A.bin B.bin [N] : 68k PC histogram difference B-A mapped to symbols (build/symbols.txt)"""
import sys, os, bisect, collections
HERE = os.path.dirname(os.path.abspath(__file__))
syms = []
for ln in open(os.path.join(HERE, '..', 'build', 'symbols.txt')):
    a, n = ln.split()
    a = int(a, 16)
    if a < 0x800000: syms.append((a, n))
syms.sort()
addrs = [a for a, _ in syms]
a = open(sys.argv[1], 'rb').read()
b = open(sys.argv[2], 'rb').read()
top = int(sys.argv[3]) if len(sys.argv) > 3 else 40
by = collections.Counter()
tot = 0
for i in range(0, len(b), 2):
    c = (b[i] << 8 | b[i + 1]) - (a[i] << 8 | a[i + 1])
    if c <= 0: continue
    pc = 0x4000 + i * 2
    k = bisect.bisect_right(addrs, pc) - 1
    by[syms[k][1] if k >= 0 else '?'] += c
    tot += c
print('samples', tot)
# group GB labels into "functions" is not possible statically; show labels and HAL routines
for n, c in by.most_common(top):
    print(f'{c:7d} {100 * c / tot:5.1f}%  {n}')
