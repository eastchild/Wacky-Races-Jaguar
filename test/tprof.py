"""tprof.py trace.log [N] : instruction counts per symbol from a MAME 68k trace"""
import sys, os, bisect, collections, re
HERE = os.path.dirname(os.path.abspath(__file__))
syms = []
for ln in open(os.path.join(HERE, '..', 'build', 'symbols.txt')):
    a, n = ln.split()
    a = int(a, 16)
    if a < 0x800000: syms.append((a, n))
syms.sort()
addrs = [a for a, _ in syms]
top = int(sys.argv[2]) if len(sys.argv) > 2 else 50
by = collections.Counter()
gb = collections.Counter()
tot = 0
rx = re.compile(r'^([0-9A-F]{6}): ')
for ln in open(sys.argv[1]):
    m = rx.match(ln)
    if not m: continue
    pc = int(m.group(1), 16)
    k = bisect.bisect_right(addrs, pc) - 1
    n = syms[k][1] if k >= 0 else '?'
    by[n] += 1
    tot += 1
    gb['GB code' if n.startswith(('g_', 's_')) else n] += 1
print('instructions', tot)
print('--- by category')
for n, c in gb.most_common(25):
    print(f'{c:8d} {100 * c / tot:5.1f}%  {n}')
print('--- GB code by 64-byte block')
blk = collections.Counter()
for n, c in by.items():
    if n.startswith(('g_', 's_')):
        b, a = n[2:].split('_')
        blk[f'{b}:{int(a, 16) & 0xFFC0:04x}'] += c
for n, c in blk.most_common(30):
    print(f'{c:8d} {100 * c / tot:5.1f}%  {n}')
print('--- by label')
for n, c in by.most_common(top):
    print(f'{c:8d} {100 * c / tot:5.1f}%  {n}')
