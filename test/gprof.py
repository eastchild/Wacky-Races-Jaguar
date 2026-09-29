"""GPU/DSP trace profile: instructions per label (symbols in the $F0xxxx range).
usage: gprof.py trace.log [build/symbols.txt]"""
import sys, re, bisect, collections

trace = sys.argv[1]
symf = sys.argv[2] if len(sys.argv) > 2 else 'build/symbols.txt'
syms = []
for line in open(symf):
    m = re.match(r'\s*([0-9A-Fa-f]{6,8})\s+(\S+)', line) or re.match(r'\s*(\S+)\s+([0-9A-Fa-f]{6,8})', line)
    if not m:
        continue
    a, n = m.groups()
    if not re.fullmatch(r'[0-9A-Fa-f]+', a):
        a, n = n, a
    a = int(a, 16)
    if 0xF00000 <= a < 0xF20000:
        syms.append((a, n))
syms.sort()
addrs = [a for a, _ in syms]
cnt = collections.Counter()
pcs = collections.Counter()
total = 0
for line in open(trace):
    m = re.match(r'([0-9A-F]{6}):\s+(\S+)\s*(.*)', line)
    if not m:
        continue
    pc = int(m.group(1), 16)
    total += 1
    pcs[pc] += 1
    i = bisect.bisect_right(addrs, pc) - 1
    cnt[syms[i][1] if i >= 0 else '?'] += 1
print('total', total)
for n, c in cnt.most_common(40):
    print(f'{c:9d} {100*c/total:5.1f}% {n}')
