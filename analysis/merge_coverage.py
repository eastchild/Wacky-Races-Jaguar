"""merge_coverage.py OUTDIR TRACEDIR [TRACEDIR...] : merge execution traces of the GB game into
one coverage directory (what gbre.py, extra_entries.py and recomp68.py read): romflags.bin
(OR, gzipped), access.txt (OR of the masks), bankatexec.txt (union of the banks), indirect.txt,
rettargets.txt, farcalls.txt, ramjumps.txt (union of the pairs). Addresses and flags only: no
ROM content. The traces come from the GB tracer used during the port (gbtrace, not part of this
repository); analysis/coverage holds the merged result, so the build does not need them."""
import sys, os, gzip, collections

out, dirs = sys.argv[1], sys.argv[2:]
os.makedirs(out, exist_ok=True)
flags = None
access = collections.defaultdict(int)
bankat = collections.defaultdict(set)
pairs = {n: set() for n in ('indirect.txt', 'rettargets.txt', 'farcalls.txt', 'ramjumps.txt')}
for d in dirs:
    p = os.path.join(d, 'romflags.bin')
    if os.path.exists(p):
        f = open(p, 'rb').read()
        flags = bytearray(f) if flags is None else bytearray(a | b for a, b in zip(flags, f))
    p = os.path.join(d, 'access.txt')
    if os.path.exists(p):
        for ln in open(p):
            k, m = ln.split()
            access[int(k, 16)] |= int(m, 16)
    p = os.path.join(d, 'bankatexec.txt')
    if os.path.exists(p):
        for ln in open(p):
            k, bs = ln.split()
            bankat[int(k, 16)] |= {int(x, 16) for x in bs.split(',')}
    for n, s in pairs.items():
        p = os.path.join(d, n)
        if os.path.exists(p):
            for ln in open(p):
                a, mid, b = ln.split()
                s.add((int(a, 16), mid, int(b, 16)))
with gzip.GzipFile(os.path.join(out, 'romflags.bin.gz'), 'wb', mtime=0) as g:
    g.write(bytes(flags))
open(os.path.join(out, 'access.txt'), 'w').write(''.join(f'{k:x} {access[k]:x}\n' for k in sorted(access)))
open(os.path.join(out, 'bankatexec.txt'), 'w').write(
    ''.join(f'{k:x} {",".join("%x" % b for b in sorted(bankat[k]))}\n' for k in sorted(bankat)))
for n, s in pairs.items():
    open(os.path.join(out, n), 'w').write(''.join(f'{a:x} {mid} {b:x}\n' for a, mid, b in sorted(s)))
print('coverage:', len(access), 'accessed addresses,', len(bankat), 'bank contexts,',
      ', '.join(f'{len(s)} {n}' for n, s in pairs.items()))
