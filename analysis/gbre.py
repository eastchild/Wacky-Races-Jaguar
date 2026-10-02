"""Recursive disassembler for the GBC ROM, seeded with dynamic coverage.

Usage: gbre.py COVDIR [COVDIR...]   -> writes build/analysis/analysis.pkl (read by recomp68.py),
bank_XX.asm listings and the code map (codemap.bin); GBRE_OUT: another output directory
Code map byte per ROM offset: 0 unknown, 1 opcode start, 2 operand, 3 data(read), 4 data(pointer/table guessed)
"""
import sys, os, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gbdis import decode, ROM

HERE = os.path.dirname(os.path.abspath(__file__))
NB = len(ROM) // 0x4000

def load_cov(dirs):
    flags = bytearray(len(ROM))
    indirect, rettgt, far = set(), set(), set()
    bankat = collections.defaultdict(set)
    ramexec = {}
    access = collections.defaultdict(int)
    for d in dirs:
        p = os.path.join(d, 'romflags.bin')
        if os.path.exists(p):
            f = open(p, 'rb').read()
        else:                                   # (coverage/romflags.bin.gz in the repository)
            import gzip
            f = gzip.open(p + '.gz', 'rb').read()
        for i, v in enumerate(f): flags[i] |= v
        for name, s in (('indirect.txt', indirect), ('rettargets.txt', rettgt), ('farcalls.txt', far)):
            p = os.path.join(d, name)
            if os.path.exists(p):
                for ln in open(p):
                    a, _, b = ln.split()
                    s.add((int(a, 16), int(b, 16)))
        p = os.path.join(d, 'bankatexec.txt')
        if os.path.exists(p):
            for ln in open(p):
                k, bs = ln.split()
                bankat[int(k, 16)] |= {int(x, 16) for x in bs.split(',')}
        p = os.path.join(d, 'access.txt')
        if os.path.exists(p):
            for ln in open(p):
                k, m = ln.split(); access[int(k, 16)] |= int(m, 16)
    return flags, indirect, rettgt, far, bankat, access

def off_of(bank, addr):
    if addr < 0x4000: return addr
    if addr < 0x8000: return bank * 0x4000 + addr - 0x4000
    return None

def addr_of(off):
    return (off // 0x4000, off if off < 0x4000 else 0x4000 + off % 0x4000)

def mem_for(bank):
    def m(a):
        a &= 0xFFFF
        if a < 0x4000: return ROM[a]
        if a < 0x8000: return ROM[bank * 0x4000 + a - 0x4000]
        return 0
    return m

class Analyzer:
    def __init__(self, dirs):
        self.flags, self.indirect, self.rettgt, self.far, self.bankat, self.access = load_cov(dirs)
        self.code = {}          # rom offset -> (length, text, target, kind, bank-context)
        self.labels = {}        # rom offset -> name
        self.xrefs = collections.defaultdict(set)
        self.ctx_bank = collections.defaultdict(set)  # bank0 offset -> possible ROMX banks
        self.unresolved = []

    def seeds(self):
        s = []
        for off, v in enumerate(self.flags):
            if v & 1:
                b, a = addr_of(off)
                s.append((off, b if b else 1))
        for vec in [0x100] + [i * 8 for i in range(8)] + [0x40, 0x48, 0x50, 0x58, 0x60]:
            s.append((vec, 1))
        for src, dst in self.indirect | self.rettgt | self.far:
            if dst < 0x1000000: s.append((dst, dst // 0x4000 or 1))
        # entries found by decoding the game's dispatch tables (extra_entries.py): "offset bank"
        p = os.path.join(HERE, 'extra_entries.txt')
        if os.path.exists(p):
            for ln in open(p):
                ln = ln.split('#')[0].split()
                if ln: s.append((int(ln[0], 16), int(ln[1], 16)))
        return s

    def jp_tables(self):
        """entries of 'jp nn' tables (computed push/ret or jp (hl) dispatch): the triples next to
        a known 'jp nn' whose target stays in the same bank window. Returns new seeds."""
        new = []
        def is_jp(o):
            if o < 0 or o + 2 >= len(ROM) or ROM[o] != 0xC3: return False
            if (o < 0x4000) != (o + 2 < 0x4000) or o // 0x4000 != (o + 2) // 0x4000: return False
            return (ROM[o + 1] | ROM[o + 2] << 8) < 0x8000
        known = [o for o, c in self.code.items() if ROM[o] == 0xC3 and c[0] == 3]
        inner = {o + i for o, c in self.code.items() for i in range(1, c[0])}
        for o in known:
            for step in (3, -3):
                n = o + step
                while is_jp(n) and n // 0x4000 == o // 0x4000 and n not in inner:
                    if n in self.code:
                        if ROM[n] != 0xC3: break
                    else:
                        b = n // 0x4000
                        new.append((n, b if b else 1))
                        self.table_entries.add(n)
                    n += step
        return new

    def unrolled_back(self):
        """unrolled code entered at a computed offset: when the p bytes before a known
        instruction repeat its first p bytes (p = a whole number of its instructions),
        they are the same unrolled step: new entry p bytes earlier. Returns new seeds."""
        new = []
        inner = {o + i for o, c in self.code.items() for i in range(1, c[0])}
        for o in list(self.code):
            if o - 1 in self.code or o - 1 in inner:
                continue                        # reached by fall-through: not a block start
            for p in range(2, 17):
                q = o - p
                if q < 0 or q // 0x4000 != o // 0x4000 or ROM[q:o] != ROM[o:o + p]:
                    continue
                n, k = o, 0                     # p bytes = whole instructions of the block?
                while n < o + p and n in self.code:
                    n += self.code[n][0]
                if n != o + p:
                    continue
                if any(q + i in self.code or q + i in inner for i in range(p)):
                    continue
                b = q // 0x4000
                new.append((q, b if b else 1))
                self.table_entries.add(q)
                break
        return new

    def run(self):
        self.table_entries = set()
        self.run_from(self.seeds())
        while True:
            new = [s for s in self.jp_tables() + self.unrolled_back() if s[0] not in self.code]
            if not new: break
            self.run_from(new)

    def run_from(self, seeds):
        work = collections.deque(seeds)
        seen = set()
        while work:
            off, cb = work.popleft()
            if (off, cb if off < 0x4000 else 0) in seen: continue
            seen.add((off, cb if off < 0x4000 else 0))
            self.trace_from(off, cb, work)

    def trace_from(self, off, curbank, work):
        """linear sweep from off until unconditional flow change. curbank = ROMX bank believed mapped."""
        bank = off // 0x4000
        addr = off if off < 0x4000 else 0x4000 + off % 0x4000
        last_a_const = None
        while True:
            o = off_of(bank if bank else curbank, addr) if addr >= 0x4000 else addr
            if o is None or o >= len(ROM): return
            if addr >= 0x4000 and bank == 0: bank = curbank
            m = mem_for(bank if addr >= 0x4000 else curbank)
            l, t, tgt, kind = decode(m, addr)
            if 'ILLEGAL' in t:
                self.unresolved.append((o, 'illegal'))
                return
            prev = self.code.get(o)
            if o < 0x4000: self.ctx_bank[o].add(curbank)
            if prev and o >= 0x4000: return
            if not prev:
                self.code[o] = (l, t, tgt, kind)
            elif o < 0x4000 and curbank in self.ctx_bank[o] and len(self.ctx_bank[o]) > 1:
                return
            # track constant bank writes: ld a,N ; ld ($2000),a
            op = ROM[o]
            if op == 0x3E: last_a_const = ROM[o + 1]
            elif op == 0xEA and m(addr + 1) | m(addr + 2) << 8 in range(0x2000, 0x3000):
                if last_a_const is not None: curbank = last_a_const
            elif op in (0xAF,) : last_a_const = 0
            elif op in (0x97,): last_a_const = 0
            else:
                # any other write to A invalidates
                if t.startswith('ld a,') or t.startswith(('add a', 'sub', 'and', 'or', 'xor', 'adc', 'sbc', 'inc a', 'dec a', 'pop af', 'rla', 'rra', 'rlca', 'rrca', 'cpl', 'daa', 'swap a', 'ldh a')):
                    last_a_const = None
            if tgt is not None:
                tb = 0 if tgt < 0x4000 else (bank if addr >= 0x4000 else curbank)
                if tgt < 0x8000:
                    to = off_of(tb, tgt)
                    self.xrefs[to].add(o)
                    work.append((to, curbank if tgt < 0x4000 else tb))
                    if to not in self.labels:
                        self.labels[to] = ('sub' if kind == 'call' else 'L') + '_%02x_%04x' % (tb, tgt)
            if kind in ('jp', 'jr', 'ret', 'jphl'):
                return
            addr += l
            if addr >= 0x8000 or (addr >= 0x4000 and bank == 0 and o < 0x4000 and addr - l < 0x4000): return

def main():
    dirs = sys.argv[1:]
    an = Analyzer(dirs)
    an.run()
    print('jp table entries added', len(an.table_entries), ' '.join('%06x' % o for o in sorted(an.table_entries)))
    cm = bytearray(len(ROM))
    for o, (l, t, tgt, kind) in an.code.items():
        cm[o] = 1
        for i in range(1, l):
            if o + i < len(cm) and cm[o + i] == 0: cm[o + i] = 2
    for i, v in enumerate(an.flags):
        if cm[i] == 0 and v & 4: cm[i] = 3
    OUT = os.environ.get('GBRE_OUT', os.path.join(HERE, '..', 'build', 'analysis'))
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, 'codemap.bin'), 'wb').write(cm)
    # stats
    per = collections.Counter()
    for o in an.code: per[o // 0x4000] += an.code[o][0]
    tot = sum(per.values())
    print('static code bytes', tot, 'dynamic opcode bytes', sum(1 for v in an.flags if v & 3))
    print(' '.join(f'{b:02x}:{per[b]}' for b in sorted(per)))
    # dynamic-only vs static
    dyn_not_static = sum(1 for i, v in enumerate(an.flags) if v & 1 and cm[i] != 1)
    print('dynamic opcodes not reached statically', dyn_not_static)
    # write listings
    for b in range(NB):
        write_bank(an, b, cm)
    import pickle
    pickle.dump({'code': an.code, 'labels': an.labels, 'ctx': dict(an.ctx_bank), 'xrefs': dict(an.xrefs)},
                open(os.path.join(OUT, 'analysis.pkl'), 'wb'))

def write_bank(an, b, cm):
    start, end = b * 0x4000, (b + 1) * 0x4000
    base = 0 if b == 0 else 0x4000
    if not any(cm[start:end]):
        return
    out = open(os.path.join(os.environ.get('GBRE_OUT', os.path.join(HERE, '..', 'build', 'analysis')), f'bank_{b:02x}.asm'), 'w')
    out.write(f'; bank {b:02x}\n')
    o = start
    while o < end:
        a = base + (o - start)
        if o in an.labels:
            xr = ' '.join('%x' % x for x in sorted(an.xrefs.get(o, []))[:6])
            out.write(f'\n{an.labels[o]}:  ; xref {xr}\n')
        if cm[o] == 1 and o in an.code:
            l, t, tgt, kind = an.code[o]
            if tgt is not None and tgt < 0x8000:
                tb = 0 if tgt < 0x4000 else b if b else None
                if tb is not None:
                    to = off_of(tb, tgt)
                    if to in an.labels: t = t.replace('$%04x' % tgt, an.labels[to])
            bs = ' '.join('%02x' % ROM[o + i] for i in range(l))
            dyn = '' if an.flags[o] & 1 else ' ;S'
            ctx = ''
            if b == 0 and o in an.ctx_bank and kind in ('call', 'jp') and tgt and tgt >= 0x4000:
                ctx = ' ; banks ' + ','.join('%02x' % x for x in sorted(an.ctx_bank[o]))
            out.write(f'  {a:04x}: {bs:<10} {t}{dyn}{ctx}\n')
            o += l
        else:
            # data run
            run = []
            while o < end and not (cm[o] == 1 and o in an.code) and o not in an.labels and len(run) < 16:
                run.append(o); o += 1
            if run:
                kinds = ''.join('r' if cm[x] == 3 else '.' for x in run)
                out.write(f'  {base + run[0] - start:04x}: db ' + ','.join('$%02x' % ROM[x] for x in run) + f'  ; {kinds}\n')
            if not run:
                o += 1
    out.close()

if __name__ == '__main__':
    main()

