"""opprof.py trace.log : 68k instructions spent per SM83 instruction form (GB code only)"""
import sys, os, bisect, collections, re, pickle
os.environ['GBDIS_RAW'] = '1'
HERE = os.path.dirname(os.path.abspath(__file__))
AN = os.path.join(HERE, '..', '..', 'analysis')
code = pickle.load(open(os.path.join(AN, 'disasm_jag', 'analysis.pkl'), 'rb'))['code']
syms = []
for ln in open(os.path.join(HERE, '..', 'build', 'symbols.txt')):
    a, n = ln.split()
    syms.append((int(a, 16), n))
syms.sort()
addrs = [a for a, _ in syms]
rx = re.compile(r'^([0-9A-F]{6}): ')
per = collections.Counter()
cnt68 = collections.Counter()
for ln in open(sys.argv[1]):
    m = rx.match(ln)
    if not m: continue
    pc = int(m.group(1), 16)
    k = bisect.bisect_right(addrs, pc) - 1
    n = syms[k][1]
    if not n.startswith('g_'): continue
    b, a = n[2:].split('_')
    b, a = int(b, 16), int(a, 16)
    off = a if a < 0x4000 else b * 0x4000 + a - 0x4000
    t = code.get(off, (0, '?'))[1]
    form = re.sub(r'\$[0-9a-f]+', 'n', t)
    cnt68[form] += 1
tot = sum(cnt68.values())
for f, c in cnt68.most_common(45):
    print(f'{c:7d} {100 * c / tot:5.1f}%  {f}')
