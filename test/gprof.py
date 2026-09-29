"""GPU trace profile: instructions per GPU label.
usage: gprof.py trace.log main.lst   (main.lst: rmac -l listing of main.s)
Labels come from the listing (addresses relative to the section, rebased on gpu_start = $F03000)."""
import sys, re, bisect, collections

trace, lst = sys.argv[1], sys.argv[2]
labels = []
pending = []
base = None
for line in open(lst, errors='replace'):
    m = re.match(r'\s*\d+\s+([0-9A-F]{8})\s+[0-9A-F]+\s+(\S+?):{1,2}\s', line)
    m2 = re.match(r'\s*\d+\s+([0-9A-F]{8})\s+[0-9A-F]+\s', line)
    ml = re.match(r'\s*\d+\s+(\w+):{1,2}\s*$', line)
    if ml:
        pending.append(ml.group(1))
        continue
    if m2:
        addr = int(m2.group(1), 16)
        names = pending + ([m.group(2)] if m else [])
        pending = []
        for n in names:
            labels.append((addr, n))
            if n == 'gpu_start':
                base = addr
    else:
        m3 = re.match(r'\s*\d+\s+[0-9A-F]{8}\s+(\w+):{1,2}', line)
if base is None:
    sys.exit('gpu_start not found in the listing')
end = [a for a, n in labels if n == 'gpu_end_addr']
end = end[0] if end else base + 0x1000
syms = sorted((0xF03000 + a - base, n) for a, n in labels if base <= a < end and not n.startswith('.'))
addrs = [a for a, _ in syms]
cnt = collections.Counter()
total = 0
for line in open(trace):
    m = re.match(r'([0-9A-F]{6}):', line)
    if not m:
        continue
    pc = int(m.group(1), 16)
    total += 1
    i = bisect.bisect_right(addrs, pc) - 1
    cnt[syms[i][1] if i >= 0 else '?'] += 1
print('total', total)
for n, c in cnt.most_common(45):
    print(f'{c:9d} {100 * c / total:5.1f}% {n}')
