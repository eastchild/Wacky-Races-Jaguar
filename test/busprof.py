"""busprof.py trace.log [N] : 68000 bus accesses (instruction words + data words) per symbol and,
in the recompiled GB code, per instruction pattern, from a MAME 68k trace (run.ps1 -TraceAt).
On the console the 68000's time is close to proportional to its bus accesses (~16 cycles each),
so this is the cost model to minimise. Instruction lengths are learnt from sequential execution
(fallback: estimated from the operands)."""
import sys, os, bisect, collections, re
HERE = os.path.dirname(os.path.abspath(__file__))
syms = []
for ln in open(os.path.join(HERE, '..', 'build', 'symbols.txt')):
    a, n = ln.split()
    a = int(a, 16)
    if a < 0x800000: syms.append((a, n))
syms.sort()
addrs = [a for a, _ in syms]
top = int(sys.argv[2]) if len(sys.argv) > 2 else 40
IDLE = ('frame_wait',)
rx = re.compile(r'^([0-9A-F]{6}): (\S+)\s*(.*)$')
lines = []
for ln in open(sys.argv[1]):
    m = rx.match(ln.rstrip())
    if m: lines.append((int(m.group(1), 16), m.group(2).lower(), m.group(3)))
FLOW = re.compile(r'^(b\w\w|bra|bsr|db\w+|jmp|jsr|rts|rte|trap)')
length = {}
for (pc, mn, op), (pc2, _, _) in zip(lines, lines[1:]):
    if 0 < pc2 - pc <= 10 and pc not in length:
        length[pc] = (pc2 - pc) // 2

def ops(s):
    out, d, cur = [], 0, ''
    for c in s:
        if c == ',' and d == 0:
            out.append(cur.strip()); cur = ''
            continue
        d += c == '('
        d -= c == ')'
        cur += c
    if cur.strip(): out.append(cur.strip())
    return out

def ismem(o):
    return '(' in o or (o.startswith('$') and not o.startswith('#'))

def est_len(mn, o):
    w = 1
    for x in o:
        if x.startswith('#'):
            if mn.startswith(('moveq', 'addq', 'subq', 'trap')): continue
            w += 2 if mn.endswith('.l') else 1
        elif x.startswith('$'):
            w += 1 if x.endswith('.w') else 2
        elif '(' in x and not x.startswith('(') and not x.startswith('-(') or ',' in x:
            w += 1
    if mn.startswith(('bra', 'bsr', 'b')) and not mn.startswith(('btst', 'bset', 'bclr', 'bchg')):
        w = 2 if not mn.endswith('.s') else 1
    return w

def data(mn, o):
    sz = 2 if mn.endswith('.l') else 1
    base = mn.split('.')[0]
    if base in ('lea', 'pea', 'jmp', 'jsr', 'moveq', 'bra', 'nop') or base.startswith('db'):
        return 2 if base == 'pea' else (2 if base == 'jsr' else 0)
    if base in ('bsr',): return 2
    if base == 'rts': return 2
    if base == 'rte': return 3
    if base == 'movem':
        regs = o[0] if not ismem(o[0]) else o[1]
        n = 0
        for part in regs.split('/'):
            if '-' in part:
                a, b = part.split('-')
                n += int(b[1]) - int(a[1]) + 1
            else:
                n += 1
        return n * sz
    if not o: return 0
    acc = 0
    if base in ('move', 'movea', 'move16'):
        if ismem(o[0]): acc += sz
        if len(o) > 1 and ismem(o[1]): acc += sz
        return acc
    if base in ('cmp', 'cmpa', 'cmpi', 'tst', 'btst', 'cmpm', 'chk'):
        return sum(sz if base != 'btst' else 1 for x in o if ismem(x))
    # read-modify-write destination, read source
    if len(o) > 1 and ismem(o[0]): acc += sz
    if ismem(o[-1]): acc += 2 * (sz if base not in ('bset', 'bclr', 'bchg') else 1)
    return acc

per = collections.Counter(); perw = collections.Counter(); perd = collections.Counter()
pat = collections.Counter(); patn = collections.Counter()
tot = 0; totw = 0; totd = 0
for pc, mn, op in lines:
    k = bisect.bisect_right(addrs, pc) - 1
    n = syms[k][1] if k >= 0 else '?'
    if n in IDLE: continue
    o = ops(op)
    w = length.get(pc) or est_len(mn, o)
    d = data(mn, o)
    if n.startswith(('g_', 's_')):
        name = 'GB code'
        p = mn + ' ' + re.sub(r'\$[0-9a-f]+', 'N', re.sub(r'#\$?[0-9a-f]+', '#N', op.lower()))
        pat[p] += w + d; patn[p] += 1
    else:
        name = n
    per[name] += w + d; perw[name] += w; perd[name] += d
    tot += w + d; totw += w; totd += d
print('bus accesses %d (instruction words %d, data %d), idle loop excluded' % (tot, totw, totd))
for k, v in per.most_common(top):
    print('  %-22s %5.1f%%  words %6d  data %6d' % (k, 100 * v / tot, perw[k], perd[k]))
gb = per['GB code']
print('-- recompiled GB code: patterns (share of GB code accesses, count)')
for k, v in pat.most_common(top):
    print('  %-44s %5.1f%%  %6d' % (k[:44], 100 * v / gb, patn[k]))
