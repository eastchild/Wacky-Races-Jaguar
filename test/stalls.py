"""stalls.py TRACE ROM SYMBOLS LISTING [section gpu|dsp]: Jaguar RISC wait states on a MAME trace
(rules: Atari/S. Moss Software Reference V10, 'Writing Fast GPU and DSP Programs')."""
import sys, re, struct, collections, bisect
trace, romf, symf, lstf = sys.argv[1:5]; sect = sys.argv[5] if len(sys.argv) > 5 else 'gpu'
rom = open(romf, 'rb').read()
syms = {l.split()[1]: int(l.split()[0], 16) for l in open(symf) if len(l.split()) == 2}
start, end, org = (syms['gpu_code'], syms['gpu_code_end'], 0xF03000) if sect == 'gpu' else (syms['dsp_code'], syms['dsp_code_end'], 0xF1B000)
code = rom[0x2100 + start - 0x4000: 0x2100 + end - 0x4000]
def dec(a):
    o = a - org; w = struct.unpack('>H', code[o:o+2])[0]; return w >> 10, (w >> 5) & 31, w & 31
# labels
lines = open(lstf, encoding='latin-1').read().splitlines()
dsp0 = [i for i, l in enumerate(lines) if re.search(r'\.org\s+\$f1b000', l, re.I)][0]
labs = []; pend = []
rng = range(0, dsp0) if sect == 'gpu' else range(dsp0, len(lines))
for i in rng:
    l = lines[i]
    ml = re.match(r'\s*\d+\s+(?:[0-9A-F]{8}\s+\S+\s+)?([A-Za-z_]\w*):{1,2}', l)
    ma = re.match(r'\s*\d+\s+([0-9A-F]{8})\s', l)
    if ml and not ma: pend.append(ml.group(1)); continue
    if ma:
        a = org + int(ma.group(1), 16)
        m2 = re.match(r'\s*\d+\s+[0-9A-F]{8}\s+\S+\s+([A-Za-z_]\w*):{1,2}', l)
        for n in pend + ([m2.group(1)] if m2 else []): labs.append((a, n))
        pend = []
labs.sort(); la = [x[0] for x in labs]
def lab(a):
    i = bisect.bisect_right(la, a) - 1; return labs[i][1] if i >= 0 else '?'
LOADS = {39, 40, 41, 42, 43, 44, 58, 59}; STORES = {45, 46, 47, 48, 49, 50, 60, 61}
NOWR = STORES | {13, 30, 31, 52, 53, 57, 36}
FLAGSET = {0,1,2,4,5,6,8,9,10,11,12,13,14,15,16,17,18,20,22,23,24,25,26,27,28,29,30,31,32,33,56,62,63}
IMM1 = {2,3,6,7,24,25,27,29,31,8,12,22,13,14,15,32,33,62,63}
def rd(op, r1, r2):
    if op in (38, 35, 51, 57, 53): return set()
    if op in (34, 37): return {r1}
    if op in LOADS:
        s = {r1} if op in (39, 40, 41, 42) else set()
        if op in (43, 58): s.add(14)
        if op in (44, 59): s.add(15)
        if op in (58, 59): s.add(r1)
        return s
    if op in STORES:
        s = {r2}
        if op in (45, 46, 47, 48): s.add(r1)
        if op in (49, 60): s.add(14)
        if op in (50, 61): s.add(15)
        if op in (60, 61): s.add(r1)
        return s
    if op == 52: return {r1}
    if op in IMM1: return {r2}
    return {r1, r2}
def wr(op, r1, r2): return None if op in NOWR else r2
st = collections.defaultdict(lambda: collections.Counter())
prev = None; prev2 = None; stalled = False; prev_a = None; idle = 0; divq = None; total = collections.Counter()
for l in open(trace):
    m = re.match(r'([0-9A-F]{6}):', l)
    if not m:
        mm = re.search(r'loops for (\d+)', l)
        if mm: idle += int(mm.group(1))
        prev = None; prev2 = None; continue
    a = int(m.group(1), 16)
    if not (org <= a < org + len(code)): prev = None; prev2 = None; continue
    op, r1, r2 = dec(a); L = lab(a); c = st[L]; c['instr'] += 1
    w = 0
    if prev:
        pop, pr1, pr2, pa, pdelay = prev
        pw = wr(pop, pr1, pr2); reads = rd(op, r1, r2)
        if pdelay and a != pa + 2: c['jump'] += 3; w += 3          # taken jump (after its delay slot)
        if pw is not None and pw in reads: c['dep'] += 1; w += 1
        # write-back of the instruction before the previous one (stage 4 while this one reads its
        # operands): concealed if this one reads its target or reads at most one register
        if prev2 and not stalled and w == 0:
            p2w = wr(prev2[0], prev2[1], prev2[2])
            if p2w is not None and len(reads) == 2 and p2w not in reads: c['wport'] += 1; w += 1
        if pop in FLAGSET and ((op in (52, 53) and r2 != 0) or op in (1, 5)): c['flags'] += 1; w += 1
        if pop in (49, 50, 60, 61): c['istore'] += 1; w += 1
    if divq and divq[0] in rd(op, r1, r2):
        left = 16 - divq[1]
        if left > 0: c['div'] += left; w += left
        divq = None
    elif divq: divq = (divq[0], divq[1] + 1 + w)
    if op == 21: divq = (r2, 0)
    stalled = w > 0; prev2 = prev
    jumped = prev is not None and prev[0] in (52, 53)
    prev = (op, r1, r2, prev[3] if (prev and prev[0] in (52, 53)) else a, op in (52, 53) and False)
    # delay-slot tracking: mark the instruction after a jump so the next one detects a taken jump
    if jumped: prev = (op, r1, r2, a, True)
for L, c in st.items():
    for k, v in c.items(): total[k] += v
cyc = lambda c: c['instr'] + c['dep'] + c['wport'] + c['flags'] + c['istore'] + c['div'] + c['jump']
print('%s: %d instructions, %d cycles with wait states (%.0f%% lost); idle loops %d instr' % (sect, total['instr'], cyc(total), 100 * (1 - total['instr'] / cyc(total)), idle))
print('%-12s %8s %8s %6s %6s %6s %6s %6s %6s %5s' % ('label', 'instr', 'cycles', 'dep', 'wport', 'flags', 'jump', 'istore', 'div', 'lost'))
for L, c in sorted(st.items(), key=lambda x: -cyc(x[1]))[:28]:
    print('%-12s %8d %8d %6d %6d %6d %6d %6d %6d %4.0f%%' % (L, c['instr'], cyc(c), c['dep'], c['wport'], c['flags'], c['jump'], c['istore'], c['div'], 100 * (1 - c['instr'] / cyc(c))))


