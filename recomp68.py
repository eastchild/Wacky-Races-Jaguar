"""SM83 (GBC) -> MC68000 (Atari Jaguar) static recompiler for Wacky Races.

Input : analysis/disasm_jag/analysis.pkl (recursive disassembly of the ORIGINAL rom, made by
        analysis/gbre.py with GBDIS_RAW=1 GBRE_OUT=analysis/disasm_jag) + dynamic coverage.
Output: gen/bank_BB.s (translated code, labels g_BB_AAAA), gen/tables.s (GB address -> code),
        gen/report.txt, gen/labels.txt

Register model (see hal/defs.inc):
    d0.b = A     d1.w = BC   d2.w = DE   d3.w = HL   (B, D, H = high bytes)
    d4   = copy of SR holding the GB flags when CCR had to be clobbered (floc 'D')
    d5-d7, a0, a1 scratch
    a2 = VRAM bank + $8000   a3 = WRAMX bank + $3000   a4 = ROMX bank - $4000
    a5 = flat GB image, GB address g at a5 + int16(g)    a6 = GPU log pointer
    a7 = GB SP (a5 + int16(SP)); GB return addresses are pushed as 16-bit GB addresses.
Pointer accesses use (An,Dn.w): the index is the sign-extended GB address.
Flags: 68k CCR Z and C have the SM83 meaning (C = borrow for sub/cp as on SM83); N/H are not
kept (daa is only used right after add/adc/sub/sbc and becomes abcd/sbcd).
"""
import os, sys, pickle, collections, re
os.environ['GBDIS_RAW'] = '1'
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
AN = os.path.join(ROOT, 'analysis')
sys.path.insert(0, AN)
from gbdis import ROM
import annot68 as annot

RG = dict(ROM0=0, ROMX=1, VRAM=2, SRAM=3, WRAM0=4, WRAMX=5, ECHO=6, OAM=7, IO=8, HRAM=9, IE=10, UNUSED=11)
ALL = frozenset('ZC')
NONE = frozenset()
Z_, C_ = frozenset('Z'), frozenset('C')
CC68 = {'nz': 'ne', 'z': 'eq', 'nc': 'cc', 'c': 'cs'}
INV = {'ne': 'eq', 'eq': 'ne', 'cc': 'cs', 'cs': 'cc'}
CCN = ['nz', 'z', 'nc', 'c']
PAIR = {'b': 'd1', 'c': 'd1', 'd': 'd2', 'e': 'd2', 'h': 'd3', 'l': 'd3'}
R8 = ['b', 'c', 'd', 'e', 'h', 'l', '(hl)', 'a']
RPN = ['bc', 'de', 'hl', 'sp']
RPR = {'bc': 'd1', 'de': 'd2', 'hl': 'd3'}


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


def gb_off(bank, addr):
    return addr if addr < 0x4000 else bank * 0x4000 + (addr - 0x4000)


def addr_of(off):
    return off if off < 0x4000 else 0x4000 + off % 0x4000


def label(off):
    b = off // 0x4000
    return 'g_%02x_%04x' % (b, addr_of(off))


def load_cov(dirs):
    acc = collections.defaultdict(int)
    bankat = collections.defaultdict(set)
    dyn = collections.defaultdict(set)       # site -> dynamic targets (indirect, ret-as-jump, ram jumps)
    kinds = {n: collections.defaultdict(set) for n in ('indirect.txt', 'rettargets.txt', 'ramjumps.txt')}
    kinds = {n: collections.defaultdict(set) for n in ('indirect.txt', 'rettargets.txt', 'ramjumps.txt')}
    for d in dirs:
        def lines(name):
            p = os.path.join(d, name)
            return open(p) if os.path.exists(p) else []
        for ln in lines('access.txt'):
            k, m = ln.split(); acc[int(k, 16)] |= int(m, 16)
        for ln in lines('bankatexec.txt'):
            k, bs = ln.split(); bankat[int(k, 16)] |= {int(x, 16) for x in bs.split(',')}
        for name in ('indirect.txt', 'rettargets.txt', 'ramjumps.txt'):
            for ln in lines(name):
                a, _, b = ln.split(); dyn[int(a, 16)].add(int(b, 16)); kinds[name][int(a, 16)].add(int(b, 16))
    return acc, bankat, dyn, kinds


class Recomp:
    def __init__(self):
        an = pickle.load(open(os.path.join(AN, 'disasm_jag', 'analysis.pkl'), 'rb'))
        self.code = an['code']
        self.ctx = an['ctx']
        self.acc, self.bankat, self.dyn, self.dynk = load_cov([os.path.join(AN, d) for d in annot.COVDIRS])
        self.warn = []
        self.nlab = 0
        self.stubs = []
        self.hle = {o: n for o, n in annot.HLE_FUNC.items()}
        self.dyn_targets = set()
        for s in self.dyn.values():
            self.dyn_targets |= {t for t in s if t < 0x1000000}

    def w(self, off, msg):
        self.warn.append('%06x: %s' % (off, msg))

    def uniq(self):
        self.nlab += 1
        return '.x%d' % self.nlab

    # ------------------------------------------------------------------ flow / flags
    def op(self, o):
        return ROM[o]

    def resolve(self, o, tgt):
        """static code offsets for a jump/call target, or None when dynamic (bank unknown / RAM)"""
        if tgt is None or tgt >= 0x8000:
            return None
        if tgt < 0x4000:
            return tgt
        if o >= 0x4000:
            return (o // 0x4000) * 0x4000 + tgt - 0x4000
        return None

    def is_cond(self, o):
        op = ROM[o]
        return op in (0x20, 0x28, 0x30, 0x38, 0xC2, 0xCA, 0xD2, 0xDA, 0xC4, 0xCC, 0xD4, 0xDC,
                      0xC0, 0xC8, 0xD0, 0xD8)

    def flags_ud(self, o):
        """(use, def) flag sets of the SM83 instruction"""
        op = ROM[o]
        if op == 0xCB:
            x, y = ROM[o + 1] >> 6, (ROM[o + 1] >> 3) & 7
            if x == 0:
                return (C_ if y in (2, 3) else NONE), ALL
            if x == 1:
                return NONE, Z_
            return NONE, NONE
        if (op & 0xC7) in (0x04, 0x05):
            return NONE, Z_
        if op in (0x07, 0x0F): return NONE, ALL
        if op in (0x17, 0x1F): return C_, ALL
        if op in (0x09, 0x19, 0x29, 0x39): return NONE, C_
        if op in (0x20, 0x28, 0xC2, 0xCA, 0xC4, 0xCC, 0xC0, 0xC8): return Z_, NONE
        if op in (0x30, 0x38, 0xD2, 0xDA, 0xD4, 0xDC, 0xD0, 0xD8): return C_, NONE
        if op == 0x27: return C_, ALL
        if op == 0x37: return NONE, C_
        if op == 0x3F: return C_, C_
        if 0x80 <= op < 0xC0 or (op & 0xC7) == 0xC6:
            y = (op >> 3) & 7
            return (C_ if y in (1, 3) else NONE), ALL
        if op == 0xF1: return NONE, ALL
        if op == 0xF5: return ALL, NONE
        if op in (0xE8, 0xF8): return NONE, ALL
        return NONE, NONE

    def succ(self, o):
        """(static successors, exits) - exits True when control may leave to unknown code"""
        l, t, tgt, kind = self.code[o]
        op = ROM[o]
        out, ex = [], False
        ft = o + l
        if kind in ('ret',) or op == 0xE9:
            return [], True
        if kind == 'retc':
            ex = True
            out.append(ft)
        elif kind in ('jp', 'jr', 'jpc', 'jrc'):
            r = self.resolve(o, tgt)
            if r is None: ex = True
            else: out.append(r)
            if kind in ('jpc', 'jrc'): out.append(ft)
        elif kind == 'call':
            r = self.resolve(o, tgt)
            if r is None or r in self.hle or (tgt is not None and tgt >= 0x8000): ex = True
            else: out.append(r)
            if self.is_cond(o): out.append(ft)
        else:
            out.append(ft)
        return out, ex

    def ret_contexts(self):
        """interprocedural data for the flags live after a ret:
        rets_of[E] = rets reachable from function entry E without entering callees,
        callers[E] = return points of the static calls to E, dyn_rets = rets whose
        return context is unknown (reti, ret-as-jump, code reached dynamically),
        gcallers = return points of calls whose callee is not known statically"""
        callers = collections.defaultdict(set)
        gcallers = set()
        for o, (l, t, tgt, kind) in self.code.items():
            if kind != 'call': continue
            op = ROM[o]
            if (op & 0xC7) == 0xC7: tgt = (op >> 3 & 7) * 8
            r = self.resolve(o, tgt)
            R = o + l
            if r is not None and r in self.code and r not in self.hle:
                callers[r].add(R)
            elif r in self.hle or (tgt is not None and tgt in annot.RAMCALL):
                pass
            elif tgt is not None and o < 0x4000 and 0x4000 <= tgt < 0x8000:
                cands = self.ctx.get(o, set()) | self.bankat.get(o, set())
                if cands:
                    for b in cands:
                        e = gb_off(b, tgt)
                        if e in self.code: callers[e].add(R)
                else:
                    gcallers.add(R)
            else:
                gcallers.add(R)
        jphl = self.dynk['indirect.txt']
        retj = self.dynk['rettargets.txt']
        def isucc(o):
            l, t, tgt, kind = self.code[o]
            ft = o + l
            # computed jumps (jp (hl), push/ret dispatch) continue the same function
            cont = [x for x in (jphl.get(o, set()) | retj.get(o, set())) if x < 0x1000000]
            if ROM[o] == 0xE9: return cont
            if kind == 'ret': return cont
            if kind == 'retc': return [ft] + cont
            if kind in ('jp', 'jr', 'jpc', 'jrc'):
                r = self.resolve(o, tgt)
                s = [r] if r is not None else []
                if r is None and tgt is not None and o < 0x4000 and 0x4000 <= tgt < 0x8000:
                    s += [gb_off(b, tgt) for b in self.ctx.get(o, set()) | self.bankat.get(o, set())]
                if kind in ('jpc', 'jrc'): s.append(ft)
                return s
            return [ft]           # call: continue at the return point
        rets_of = {}
        reached_by = collections.defaultdict(set)
        ramt = {x for s in self.dynk['ramjumps.txt'].values() for x in s if x < 0x1000000}
        unknown_entries = ramt | set(annot.ENTRY)
        entries = set(callers) | unknown_entries
        for e in entries:
            if e not in self.code: continue
            seen, st, rs = {e}, [e], set()
            while st:
                o = st.pop()
                if self.code[o][3] in ('ret', 'retc'): rs.add(o)
                for x in isucc(o):
                    if x in self.code and x not in seen:
                        seen.add(x); st.append(x)
            rets_of[e] = rs
            for r in rs: reached_by[r].add(e)
        dyn_rets = set()
        for o, (l, t, tgt, kind) in self.code.items():
            if kind not in ('ret', 'retc'): continue
            if ROM[o] == 0xD9 or o in retj or not reached_by[o]:
                dyn_rets.add(o)
            elif any(e in unknown_entries or e not in callers for e in reached_by[o]):
                dyn_rets.add(o)
        return callers, gcallers, reached_by, dyn_rets

    def liveness(self):
        callers, gcallers, reached_by, dyn_rets = self.ret_contexts()
        ret_lo = {o: NONE for o in reached_by}
        for o in dyn_rets: ret_lo[o] = ALL
        for it in range(20):
            self.liveness_pass(ret_lo)
            glob = NONE
            for R in gcallers: glob = glob | self.live_in.get(R, ALL)
            need = {e: NONE for e in callers}
            for e, Rs in callers.items():
                for R in Rs: need[e] = need[e] | self.live_in.get(R, ALL)
            changed = False
            for r, es in reached_by.items():
                if r in dyn_rets: continue
                v = glob
                for e in es: v = v | need.get(e, ALL)
                if v != ret_lo.get(r):
                    ret_lo[r] = ret_lo.get(r, NONE) | v
                    changed = True
            if not changed: break
        nall = sum(1 for v in ret_lo.values() if v == ALL)
        if os.environ.get('RECOMP_DIAG'):
            print('gcallers', len(gcallers), 'glob', sorted(glob),
                  'live gcallers', sorted('%06x' % R for R in gcallers if self.live_in.get(R, ALL))[:20])
            reasons = collections.Counter()
            for o in dyn_rets:
                if ROM[o] == 0xD9: reasons['reti'] += 1
                elif o in self.dyn: reasons['ret-as-jump'] += 1
                elif not reached_by[o]: reasons['unreached'] += 1
                else:
                    for e in reached_by[o]:
                        if e in self.dyn_targets: reasons['dyn entry %06x' % e] += 1
                        elif e in annot.ENTRY: reasons['entry %06x' % e] += 1
                        elif e not in callers: reasons['no callers %06x' % e] += 1
            print(reasons.most_common(30))
            live_R = collections.Counter()
            for e, Rs in callers.items():
                for R in Rs:
                    if self.live_in.get(R, ALL): live_R[''.join(sorted(self.live_in.get(R, ALL)))] += 1
            print('return points with live flags', live_R)
        print(f'flags after ret: {len(ret_lo)} rets, {nall} with all flags live ({len(dyn_rets)} unknown context), {it + 1} passes')

    def liveness_pass(self, ret_lo):
        use, dfn, succ = {}, {}, {}
        for o in self.code:
            use[o], dfn[o] = self.flags_ud(o)
            s, ex = self.succ(o)
            succ[o] = (s, ex)
        live_in = {o: NONE for o in self.code}
        preds = collections.defaultdict(list)
        for o, (s, ex) in succ.items():
            for x in s: preds[x].append(o)
        work = collections.deque(self.code)
        inq = set(self.code)
        live_out = {}
        def exit_lo(o, ex):
            if not ex: return NONE
            if o in ret_lo: return ret_lo[o]
            return ALL
        while work:
            o = work.popleft(); inq.discard(o)
            s, ex = succ[o]
            lo = exit_lo(o, ex)
            for x in s:
                lo = lo | (live_in.get(x, ALL) if x in self.code else ALL)
            live_out[o] = lo
            li = use[o] | (lo - dfn[o])
            if li != live_in[o]:
                live_in[o] = li
                for p in preds[o]:
                    if p not in inq: work.append(p); inq.add(p)
        for o in self.code:
            if o not in live_out:
                s, ex = succ[o]
                lo = exit_lo(o, ex)
                for x in s: lo = lo | (live_in.get(x, ALL) if x in self.code else ALL)
                live_out[o] = lo
        self.live_in, self.live_out, self.dfn = live_in, live_out, dfn

    def canonical_points(self):
        """instructions that are entered by static jumps/calls/returns: flags must be in CCR there"""
        c = set(annot.ENTRY) | self.dyn_targets
        for o, (l, t, tgt, kind) in self.code.items():
            if kind in ('jp', 'jr', 'jpc', 'jrc', 'call'):
                r = self.resolve(o, tgt)
                if r is not None: c.add(r)
                if tgt is not None and o < 0x4000 and 0x4000 <= tgt < 0x8000:
                    for b in self.ctx.get(o, set()) | self.bankat.get(o, set()):
                        c.add(gb_off(b, tgt))
            if kind == 'call':
                c.add(o + l)             # return point
            if ROM[o] == 0xCB: pass
        self.canon = c

    # ------------------------------------------------------------------ constants
    K = {}

    def known(self, rp):
        hi, lo = self.K.get(rp[0]), self.K.get(rp[1])
        if hi is None or lo is None: return None
        return hi << 8 | lo

    def kstep(self, off):
        l, t, tgt, kind = self.code[off]
        op = ROM[off]
        K = self.K
        n8 = ROM[off + 1] if l > 1 else 0
        n16 = (ROM[off + 1] | ROM[off + 2] << 8) if l > 2 else 0
        def setp(rp, v):
            if v is None: K[rp[0]] = K[rp[1]] = None
            else: K[rp[0]] = (v >> 8) & 255; K[rp[1]] = v & 255
        if kind == 'call' or kind in ('jp', 'jr', 'ret', 'jphl'):
            K.clear(); return
        if op in (0x01, 0x11, 0x21): setp(['bc', 'de', 'hl'][op >> 4], n16); return
        if op in (0x03, 0x13, 0x23, 0x0B, 0x1B, 0x2B):
            rp = ['bc', 'de', 'hl'][op >> 4 & 3]
            v = self.known(rp)
            setp(rp, None if v is None else (v + (1 if op & 8 == 0 else -1)) & 0xFFFF); return
        if op in (0x22, 0x2A, 0x32, 0x3A):
            v = self.known('hl')
            setp('hl', None if v is None else (v + (1 if op in (0x22, 0x2A) else -1)) & 0xFFFF); return
        if op in (0x09, 0x19, 0x29, 0x39):
            a = self.known('hl'); b = self.known(['bc', 'de', 'hl', 'sp'][op >> 4 & 3]) if op != 0x39 else None
            setp('hl', None if a is None or b is None else (a + b) & 0xFFFF); return
        if op in (0xC1, 0xD1, 0xE1): setp(['bc', 'de', 'hl'][op >> 4 & 3], None); return
        if op == 0xF8: setp('hl', None); return
        R = ['b', 'c', 'd', 'e', 'h', 'l', None, None]
        if 0x40 <= op < 0x80 and op != 0x76:
            d, s = R[(op >> 3) & 7], (op & 7)
            if d: K[d] = K.get(R[s]) if R[s] else None
            return
        if (op & 0xC7) == 0x06:
            d = R[(op >> 3) & 7]
            if d: K[d] = n8
            return
        if (op & 0xC7) in (0x04, 0x05):
            d = R[(op >> 3) & 7]
            if d and K.get(d) is not None: K[d] = (K[d] + (1 if (op & 7) == 4 else -1)) & 255
            return
        if op == 0xCB:
            o2 = ROM[off + 1]; d = R[o2 & 7]
            if d is None: return
            x, y = o2 >> 6, (o2 >> 3) & 7
            if x == 1: return
            v = K.get(d)
            if v is None: K[d] = None; return
            if x == 2: K[d] = v & ~(1 << y)
            elif x == 3: K[d] = v | (1 << y)
            else: K[d] = None

    # ------------------------------------------------------------------ regions
    def static_kind(self, a, write):
        a &= 0xFFFF
        if a < 0x8000: return 'M' if write else ('F' if a < 0x4000 else 'X')
        if a < 0xA000: return 'V'
        if a < 0xC000: return 'S'
        if a < 0xD000: return 'F'
        if a < 0xE000: return 'WX'
        if a < 0xFE00: return 'G'
        if a < 0xFEA0: return 'O' if write else 'F'
        if a < 0xFF00: return 'F'
        if a < 0xFF80: return 'I'
        return 'F'

    def mem_kind(self, off, write, rp):
        """region class of a pointer access -> 'F','X','V','WX','O','I','M','G'"""
        if off in annot.REGION: return annot.REGION[off]
        if rp is not None:
            a = self.known(rp)
            if a is not None:
                return self.static_kind(a, write)
        m = self.acc.get(off, 0)
        bits = (m >> (16 if write else 0)) & 0xFFFF
        if bits == 0:
            bits = (m >> (0 if write else 16)) & 0xFFFF
        if bits == 0:
            self.w(off, 'region unknown -> generic')
            return 'G'
        kinds = set()
        for r, n in RG.items():
            if not bits & (1 << n): continue
            if r in ('ROM0', 'WRAM0', 'HRAM', 'IE'): kinds.add('M' if write and r == 'ROM0' else 'F')
            elif r == 'OAM': kinds.add('O' if write else 'F')
            elif r == 'ROMX': kinds.add('M' if write else 'X')
            elif r == 'VRAM': kinds.add('V')
            elif r == 'WRAMX': kinds.add('WX')
            elif r == 'IO': kinds.add('I')
            else: kinds.add('G')
        if len(kinds) == 1: return kinds.pop()
        return 'G'

    BASE = {'F': 'a5', 'X': 'a4', 'V': 'a2', 'WX': 'a3'}

    # ------------------------------------------------------------------ flag location handling
    def clobber(self, out):
        """about to emit code that destroys CCR without defining the GB flags"""
        if self.floc == 'C' and self.lo_now:
            out.append('move sr,d4')
            self.floc = 'D'

    def need_ccr(self, out):
        if self.floc == 'D':
            out.append('move d4,ccr')
            self.floc = 'C'

    def defined(self, out, defs, op_lines, keeps_other=False):
        """op_lines set the flags in 'defs'; other live flags must survive"""
        survive = self.lo_now - defs
        if not survive:
            out += op_lines
            self.floc = 'C'
            return
        if keeps_other and self.floc == 'C':
            out += op_lines          # the 68k op leaves the other flags untouched
            return
        if self.floc == 'C':
            out.append('move sr,d4')
        out += op_lines
        m = (4 if 'Z' in defs else 0) | (0x11 if 'C' in defs else 0)
        out += ['move sr,d5', f'andi.w #${m:02x},d5', f'andi.w #${(~m) & 0xFFFF:04x},d4', 'or.w d5,d4']
        self.floc = 'D'

    # ------------------------------------------------------------------ operand helpers
    def get8(self, r):
        """(lines, operand) giving register r as a byte operand"""
        if r == 'a': return [], 'd0'
        if r in 'cel': return [], PAIR[r]
        return [f'move.w {PAIR[r]},-(a7)', 'move.b (a7)+,d7'], 'd7'

    def put8(self, r, src):
        """lines storing byte operand src into register r (clobber CCR)"""
        if r == 'a': return [] if src == 'd0' else [f'move.b {src},d0']
        if r in 'cel': return [] if src == PAIR[r] else [f'move.b {src},{PAIR[r]}']
        p = PAIR[r]
        if src.startswith('#'):
            n = int(src[2:], 16) if src.startswith('#$') else int(src[1:])
            return [f'andi.w #$00ff,{p}'] + ([f'ori.w #${n << 8:04x},{p}'] if n else [])
        return [f'move.w {p},-(a7)', f'move.b {src},(a7)', f'movem.w (a7)+,{p}']

    # memory read of (rp) -> returns (lines, operand) ; operand is a memory EA or 'd7'
    def mem_read(self, off, rp):
        k = self.mem_kind(off, False, rp)
        reg = RPR[rp]
        if k in self.BASE:
            return [], f'({self.BASE[k]},{reg}.w)'
        if k == 'I' and self.known(rp) is not None:
            a = self.known(rp)
            return self.io_read(a)
        if k == 'I':
            return [f'move.w {reg},d6', 'jsr io_rd'], 'd7'
        return [f'move.w {reg},d6', 'jsr gb_rd'], 'd7'

    def mem_write(self, off, rp, src):
        """lines writing byte operand src to (rp)"""
        k = self.mem_kind(off, True, rp)
        reg = RPR[rp]
        if k in ('F', 'WX'):
            return [f'move.b {src},({self.BASE[k]},{reg}.w)']
        pre = [] if src == 'd7' else [f'move.b {src},d7']
        if k == 'V':
            return pre + [f'move.w {reg},d6', 'jsr vram_wr']
        if k == 'I' and self.known(rp) is not None:
            return pre + self.io_write(self.known(rp))
        if k == 'I':
            return pre + [f'move.w {reg},d6', 'jsr io_wr']
        if k == 'O':
            return pre + [f'move.w {reg},d6', 'jsr oam_wr']
        return pre + [f'move.w {reg},d6', 'jsr gb_wr']

    def io_read(self, a):
        a &= 0xFFFF
        if 0xFF00 <= a < 0xFF80 and (a & 0xFF) in annot.IOR:
            return [f'move.w #${a:04x},d6', f'jsr {annot.IOR[a & 0xFF]}'], 'd7'
        return [], f'{s16(a)}(a5)'

    def io_write(self, a):
        """value in d7"""
        a &= 0xFFFF
        if 0xFF00 <= a < 0xFF80 and (a & 0xFF) in annot.IOW:
            return [f'move.w #${a:04x},d6', f'jsr {annot.IOW[a & 0xFF]}']
        return [f'move.b d7,{s16(a)}(a5)']

    def abs_read(self, off, a):
        """(lines, operand) for ld a,(nn)"""
        k = self.static_kind(a, False)
        if k == 'F': return [], f'{s16(a)}(a5)'
        if k == 'X': return [], f'${a:04x}(a4)'
        if k == 'V': return [], f'{s16(a)}(a2)'
        if k == 'WX': return [], f'{s16(a)}(a3)'
        if k == 'I': return self.io_read(a)
        return [f'move.w #${a:04x},d6', 'jsr gb_rd'], 'd7'

    def abs_write(self, off, a):
        """lines for ld (nn),a (value in d0)"""
        k = self.static_kind(a, True)
        if k == 'F': return [f'move.b d0,{s16(a)}(a5)']
        if k == 'WX': return [f'move.b d0,{s16(a)}(a3)']
        if k == 'I': return ['move.b d0,d7'] + self.io_write(a)
        if k == 'M':
            if 0x2000 <= a < 0x3000: return ['move.b d0,d7', 'jsr mbc_bank']
            return [f'; write to ${a:04x} ignored']
        if k == 'V': return ['move.b d0,d7', f'move.w #${a:04x},d6', 'jsr vram_wr']
        if k == 'O': return ['move.b d0,d7', f'move.w #${a:04x},d6', 'jsr oam_wr']
        return ['move.b d0,d7', f'move.w #${a:04x},d6', 'jsr gb_wr']

    # ------------------------------------------------------------------ control flow helpers
    def target_label(self, o, tgt):
        r = self.resolve(o, tgt)
        if r is None: return None
        if r in self.hle: return self.hle[r]
        if r not in self.code:
            self.w(o, 'target %06x not decoded' % r)
            return 'gb_bad_static'
        return label(r)

    def near(self, o, r):
        return r is not None and r // 0x4000 == o // 0x4000 and abs(r - o) < 1000

    def jump(self, o, tgt, cond, out):
        """emit an (optionally conditional) jump; flags already in CCR if needed"""
        r = self.resolve(o, tgt)
        if tgt >= 0x8000:
            if tgt in annot.RAMCALL:
                self.w(o, 'jump to RAM routine %04x' % tgt)
            dest = None
        else:
            dest = self.target_label(o, tgt)
        if dest is None:
            # dynamic: dispatch on the GB address with the current bank
            if 0x4000 <= tgt < 0x8000:
                # ROMX address, bank known only at run time: entry of the current bank's table
                # (cur_dtab is biased by -$10000; no flag is touched)
                seq = ['movea.l cur_dtab.w,a0', f'adda.l #${tgt * 4:x},a0', 'movea.l (a0),a0', 'jmp (a0)']
            else:
                seq = [f'movea.w #${tgt:04x},a0', 'jmp gb_jump']
        else:
            seq = None
        if cond is None:
            out += seq if seq else [f'jmp {dest}']
            return
        c = CC68[cond]
        if seq is None and self.near(o, r) and dest.startswith('g_'):
            out.append(f'b{c}.w {dest}')
            return
        x = self.uniq()
        out += [f'b{INV[c]}.s {x}'] + (seq if seq else [f'jmp {dest}']) + [f'{x}:']

    def push_const(self, v, out):
        if self.floc_live_at_target:
            out += [f'movea.w #${v:04x},a0', 'movem.w a0,-(a7)']
        else:
            out.append(f'move.w #${v:04x},-(a7)')

    # ------------------------------------------------------------------ translation
    def tr(self, o):
        l, t, tgt, kind = self.code[o]
        op = ROM[o]
        n8 = ROM[o + 1] if l > 1 else 0
        n16 = (ROM[o + 1] | ROM[o + 2] << 8) if l > 2 else 0
        out = []
        x, y, z, p, q = op >> 6, (op >> 3) & 7, op & 7, (op >> 4) & 3, (op >> 3) & 1

        # ---------------- CB prefix
        if op == 0xCB:
            o2 = ROM[o + 1]; cx, cy, cz = o2 >> 6, (o2 >> 3) & 7, o2 & 7
            r = R8[cz]
            if cx == 1:   # bit
                if r == '(hl)':
                    k = self.mem_kind(o, False, 'hl')
                    if k in self.BASE:
                        self.defined(out, Z_, [f'btst #{cy},({self.BASE[k]},d3.w)'], keeps_other=True)
                    else:
                        pre, src = self.mem_read(o, 'hl')
                        self.defined(out, Z_, pre + [f'btst #{cy},{src}'])
                    return out
                bitn = cy + (8 if r in 'bdh' else 0)
                reg = 'd0' if r == 'a' else PAIR[r]
                self.defined(out, Z_, [f'btst #{bitn},{reg}'], keeps_other=True)
                return out
            if cx in (2, 3):  # res / set
                ins = 'bclr' if cx == 2 else 'bset'
                self.clobber(out)
                if r == '(hl)':
                    k = self.mem_kind(o, True, 'hl')
                    if k in ('F', 'WX'):
                        out.append(f'{ins} #{cy},({self.BASE[k]},d3.w)')
                    else:
                        pre, src = self.mem_read(o, 'hl')
                        out += pre
                        if src != 'd7': out.append(f'move.b {src},d7')
                        out.append(f'{ins} #{cy},d7')
                        out += self.mem_write(o, 'hl', 'd7')
                    return out
                bitn = cy + (8 if r in 'bdh' else 0)
                reg = 'd0' if r == 'a' else PAIR[r]
                out.append(f'{ins} #{bitn},{reg}')
                return out
            # rotates / shifts
            return self.rot(o, cy, r, out)

        # ---------------- ld r,r'
        if x == 1:
            if op == 0x76:
                self.clobber(out)
                return out + ['jsr hal_halt']
            d, s = R8[y], R8[z]
            if d == s: return out
            self.clobber(out)
            if s == '(hl)':
                pre, src = self.mem_read(o, 'hl')
                return out + pre + self.put8(d, src)
            if d == '(hl)':
                pre, src = self.get8(s)
                return out + pre + self.mem_write(o, 'hl', src)
            pre, src = self.get8(s)
            return out + pre + self.put8(d, src)

        # ---------------- ALU a,r / a,n
        if x == 2 or (x == 3 and z == 6):
            if x == 2 and z == 6:
                pre, src = self.mem_read(o, 'hl')
            elif x == 2:
                pre, src = self.get8(R8[z])
            else:
                pre, src = [], f'#${n8:02x}'
            return self.alu(o, y, pre, src, out)

        # ---------------- misc
        if op == 0x00: return out
        if op == 0x10: return ['; stop']
        if op == 0xF3: return ['sf gb_ime']
        if op == 0xFB:
            # EI: a pending interrupt (IF) is taken at once
            self.clobber(out)
            return out + ['jsr hal_ei']
        if op in (0x07, 0x0F, 0x17, 0x1F):
            ins = {0x07: 'rol', 0x0F: 'ror', 0x17: 'roxl', 0x1F: 'roxr'}[op]
            lines = []
            if op in (0x17, 0x1F):
                self.need_ccr(lines)
                lines += ['scs d5', 'add.b d5,d5']      # X = C
            lines.append(f'{ins}.b #1,d0')
            if 'Z' in self.lo_now:
                lines.append('andi #$fb,ccr')           # SM83 clears Z
            self.defined(out, ALL, lines)
            return out
        if op == 0x27:
            if o in self.daa_done: return ['; daa (merged)']
            self.w(o, 'daa not after add/sub n')
            return ['jsr gb_panic']
        if op == 0x2F:
            self.clobber(out)
            return out + ['not.b d0']
        if op == 0x37:
            if self.lo_now - C_: self.need_ccr(out)
            out.append('ori #$11,ccr')
            if self.floc == 'D': self.floc = 'C'
            return out
        if op == 0x3F:
            self.need_ccr(out)
            out.append('eori #$11,ccr')
            return out

        # 16-bit
        if x == 0 and z == 1:
            if q == 0:
                if p == 3:
                    return [f'lea {s16(n16)}(a5),a7']
                self.clobber(out)
                return out + [f'move.w #${n16:04x},{RPR[RPN[p]]}']
            # add hl,rr
            if p == 3:
                self.w(o, 'add hl,sp')
                lines = ['move.l a7,d5', 'sub.l a5,d5', 'add.w d5,d3']
            else:
                lines = [f'add.w {RPR[RPN[p]]},d3']
            self.defined(out, C_, lines)
            return out
        if x == 0 and z == 3:
            if p == 3:
                return [f"{'addq' if q == 0 else 'subq'}.l #1,a7"]
            self.clobber(out)
            return out + [f"{'addq' if q == 0 else 'subq'}.w #1,{RPR[RPN[p]]}"]
        if x == 0 and z in (4, 5):
            ins = 'addq' if z == 4 else 'subq'
            r = R8[y]
            if r == '(hl)':
                k = self.mem_kind(o, True, 'hl')
                if k in ('F', 'WX'):
                    lines = [f'{ins}.b #1,({self.BASE[k]},d3.w)']
                else:
                    pre, src = self.mem_read(o, 'hl')
                    lines = pre + ([] if src == 'd7' else [f'move.b {src},d7']) + [f'{ins}.b #1,d7', 'move sr,d5']
                    lines += self.mem_write(o, 'hl', 'd7') + ['move d5,ccr']
            elif r in 'bdh':
                pr = PAIR[r]
                lines = [f"{'addi' if z == 4 else 'subi'}.w #$100,{pr}"]
                if 'Z' in self.lo_now:
                    lines += [f'move.w {pr},d7', 'andi.w #$ff00,d7']
            else:
                lines = [f'{ins}.b #1,{"d0" if r == "a" else PAIR[r]}']
            self.defined(out, Z_, lines)
            return out
        if x == 0 and z == 6:
            r = R8[y]
            self.clobber(out)
            if r == '(hl)':
                return out + self.mem_write(o, 'hl', f'#${n8:02x}')
            return out + self.put8(r, f'#${n8:02x}')
        if x == 0 and z == 2:
            if op in (0x02, 0x12, 0x0A, 0x1A):
                rp = 'bc' if op in (0x02, 0x0A) else 'de'
                self.clobber(out)
                if op in (0x02, 0x12):
                    return out + self.mem_write(o, rp, 'd0')
                pre, src = self.mem_read(o, rp)
                return out + pre + self.put8('a', src)
            wr = op in (0x22, 0x32)
            step = 'addq.w #1,d3' if op in (0x22, 0x2A) else 'subq.w #1,d3'
            self.clobber(out)
            if wr:
                return out + self.mem_write(o, 'hl', 'd0') + [step]
            pre, src = self.mem_read(o, 'hl')
            return out + pre + self.put8('a', src) + [step]
        if op == 0x08:
            self.clobber(out)
            self.w(o, 'ld (nn),sp')
            return out + ['move.l a7,d5', 'sub.l a5,d5', f'move.b d5,{s16(n16)}(a5)', 'lsr.w #8,d5',
                          f'move.b d5,{s16(n16 + 1)}(a5)']

        # jumps
        if kind in ('jr', 'jp', 'jrc', 'jpc'):
            cond = None
            if kind in ('jrc', 'jpc'):
                cond = CCN[y - 4] if x == 0 else CCN[y]
            if self.live_in_tgt(o, tgt) or cond:
                self.need_ccr(out)
            elif self.floc == 'D':
                pass
            self.jump(o, tgt, cond, out)
            return out
        if kind == 'call':
            cond = None if op == 0xCD or (x == 3 and z == 7) else CCN[y]
            if x == 3 and z == 7: tgt = y * 8
            ret = addr_of(o + l)
            li = self.live_in_tgt(o, tgt)
            if cond or li: self.need_ccr(out)
            skip = None
            if cond:
                skip = self.uniq()
                out.append(f'b{INV[CC68[cond]]}.w {skip}')
            r = self.resolve(o, tgt)
            if r in self.hle:
                out.append(f'jsr {self.hle[r]}')
            elif tgt >= 0x8000 and tgt in annot.RAMCALL:
                out.append(f'jsr {annot.RAMCALL[tgt]}')
            else:
                self.floc_live_at_target = bool(li)
                self.push_const(ret, out)
                self.jump(o, tgt, None, out)
            if skip: out.append(f'{skip}:')
            return out
        if op == 0xC9:
            self.need_ccr(out)
            return out + ['jmp gb_ret']
        if op == 0xD9:
            self.need_ccr(out)
            return out + ['st gb_ime', 'jmp gb_ret']
        if kind == 'retc':
            self.need_ccr(out)
            s = self.uniq()
            return out + [f'b{INV[CC68[CCN[y]]]}.s {s}', 'jmp gb_ret', f'{s}:']
        if op == 0xE9:
            self.need_ccr(out)
            return out + ['movea.w d3,a0', 'jmp gb_jump']

        # stack
        if x == 3 and z == 1 and q == 0:
            if p == 3:   # pop af
                lines = ['move.b 1(a7),d5', 'move.b (a7)+,d0']
                if self.lo_now:
                    lines += ['lsr.b #4,d5', 'andi.w #$0f,d5', 'lea ccr_of_f,a0', 'move.b (a0,d5.w),d4']
                    self.floc = 'D'
                return lines
            r = RPR[RPN[p]]
            if self.lo_now:
                return [f'movem.w (a7)+,{r}']
            return [f'move.w (a7)+,{r}']
        if x == 3 and z == 5 and q == 0:
            if p == 3:   # push af
                if self.floc == 'C':
                    out.append('move sr,d4')
                    self.floc = 'D'
                return out + ['move.w d4,d5', 'andi.w #5,d5', 'lea f_of_ccr,a0', 'move.b (a0,d5.w),d5',
                              'move.b d0,-(a7)', 'move.b d5,1(a7)']
            r = RPR[RPN[p]]
            if self.lo_now:
                return [f'movem.w {r},-(a7)']
            return [f'move.w {r},-(a7)']
        if op == 0xF9:
            return ['lea (a5,d3.w),a7']
        if op == 0xE8:
            self.w(o, 'add sp,e')
            e = (n8 ^ 0x80) - 0x80
            return [f'lea {e}(a7),a7']
        if op == 0xF8:
            e = (n8 ^ 0x80) - 0x80
            self.w(o, 'ld hl,sp+e (flags approximated)')
            self.clobber(out)
            return out + ['move.l a7,d3', 'sub.l a5,d3', f'add.w #{e},d3']

        # ldh / (c) / absolute
        if op == 0xE0:
            self.clobber(out)
            return out + (['move.b d0,d7'] + self.io_write(0xFF00 + n8) if (n8 < 0x80 and n8 in annot.IOW)
                          else [f'move.b d0,{s16(0xFF00 + n8)}(a5)'])
        if op == 0xF0:
            self.clobber(out)
            if n8 == 0x44 and ROM[o + 2] == 0xFE and ROM[o + 4] == 0x20 and ROM[o + 5] == 0xFA:
                # "ldh a,(LY) / cp n / jr nz,self": wait natively for line n
                return out + [f'move.b #${ROM[o + 3]:02x},d7', 'jsr hal_wait_lyn', 'move.b d7,d0']
            pre, src = self.io_read(0xFF00 + n8)
            return out + pre + [f'move.b {src},d0']
        if op in (0xE2, 0xF2) and self.K.get('c') is not None:
            a = 0xFF00 + self.K['c']
            self.clobber(out)
            if op == 0xE2:
                if a >= 0xFF80 or (a & 0xFF) not in annot.IOW:
                    return out + [f'move.b d0,{s16(a)}(a5)']
                return out + ['move.b d0,d7'] + self.io_write(a)
            pre, src = self.io_read(a)
            return out + pre + [f'move.b {src},d0']
        if op == 0xE2:
            self.clobber(out)
            return out + ['move.b d0,d7', 'move.w d1,d6', 'ori.w #$ff00,d6', 'jsr io_wr']
        if op == 0xF2:
            self.clobber(out)
            return out + ['move.w d1,d6', 'ori.w #$ff00,d6', 'jsr io_rd', 'move.b d7,d0']
        if op == 0xEA:
            self.clobber(out)
            return out + self.abs_write(o, n16)
        if op == 0xFA:
            self.clobber(out)
            pre, src = self.abs_read(o, n16)
            return out + pre + [f'move.b {src},d0']

        self.w(o, 'untranslated opcode %02x %s' % (op, t))
        return ['jsr gb_panic']

    def live_in_tgt(self, o, tgt):
        r = self.resolve(o, tgt)
        if r is None or r not in self.code: return True
        return bool(self.live_in[r])

    def alu(self, o, y, pre, src, out):
        """y: 0 add 1 adc 2 sub 3 sbc 4 and 5 xor 6 or 7 cp; pre/src give the operand"""
        l = []
        nxt = o + self.code[o][0]
        daa = nxt in self.code and ROM[nxt] == 0x27 and nxt not in self.canon
        if y in (1, 3) and daa:
            # adc/sbc followed by daa: abcd/sbcd with X = SM83 carry, Z preset
            self.daa_done.add(nxt)
            self.need_ccr(out)
            out.append('scs d5')
            l += pre + [f'move.b {src},d7', 'andi.b #$15,d5', 'ori.b #$04,d5', 'move.w d5,ccr',
                        f"{'abcd' if y == 1 else 'sbcd'} d7,d0"]
            self.defined(out, ALL, l)
            return out
        if y in (1, 3) and self.xvalid and 'Z' not in self.lo_now and not any('jsr' in p for p in pre):
            # X still holds the SM83 carry: plain addx/subx (Z is not needed afterwards)
            l += pre
            if not (src.startswith('d') and len(src) == 2):
                l.append(f'move.b {src},d7'); src = 'd7'
            l.append(f"{'addx' if y == 1 else 'subx'}.b {src},d0")
            self.defined(out, ALL, l)
            return out
        if y in (1, 3):
            self.need_ccr(out)
            out.append('scs d5')
            l += pre
            if not (src.startswith('d') and len(src) == 2):
                l.append(f'move.b {src},d7'); src = 'd7'
            l += ['andi.b #$15,d5', 'ori.b #$04,d5', 'move.w d5,ccr',
                  f"{'addx' if y == 1 else 'subx'}.b {src},d0"]
            self.defined(out, ALL, l)
            return out
        l += pre
        # daa merge: add / sub followed by daa -> abcd / sbcd
        if y in (0, 2) and daa:
            self.daa_done.add(nxt)
            l += [f'move.b {src},d7', 'move #4,ccr', f"{'abcd' if y == 0 else 'sbcd'} d7,d0"]
            self.defined(out, ALL, l)
            return out
        if y == 5:
            if src == 'd0':
                l = ['moveq #0,d0']
            elif src.startswith('#'):
                l.append(f'eori.b {src},d0')
            else:
                if not (src.startswith('d') and len(src) == 2):
                    l.append(f'move.b {src},d7'); src = 'd7'
                l.append(f'eor.b {src},d0')
        else:
            ins = {0: 'add', 2: 'sub', 4: 'and', 6: 'or', 7: 'cmp'}[y]
            if src.startswith('#') and ins != 'cmp':
                ins += 'i'
            l.append(f'{ins}.b {src},d0')
        self.defined(out, ALL, l)
        return out

    def rot(self, o, cy, r, out):
        ins = ['rol', 'ror', 'roxl', 'roxr', 'asl', 'asr', None, 'lsr'][cy]
        l = []
        if cy in (2, 3):
            self.need_ccr(out)
            out.append('scs d5')
        if r == '(hl)':
            pre, src = self.mem_read(o, 'hl')
            l += pre
            if src != 'd7': l.append(f'move.b {src},d7')
            reg = 'd7'
        elif r in 'bdh':
            l += [f'move.w {PAIR[r]},-(a7)', 'move.b (a7)+,d7']
            reg = 'd7'
        else:
            reg = 'd0' if r == 'a' else PAIR[r]
        if cy in (2, 3):
            l.append('add.b d5,d5')                     # X = saved C (HAL calls keep d5)
        if cy == 6:
            l += [f'rol.b #4,{reg}', f'tst.b {reg}']
        else:
            l.append(f'{ins}.b #1,{reg}')
        if reg == 'd7':
            store = self.mem_write(o, 'hl', 'd7') if r == '(hl)' else \
                [f'move.w {PAIR[r]},-(a7)', 'move.b d7,(a7)', f'movem.w (a7)+,{PAIR[r]}']
            if self.lo_now:
                l += ['move sr,d5'] + store + ['move d5,ccr']
            else:
                l += store
        self.defined(out, ALL, l)
        return out

    # ------------------------------------------------------------------ X flag tracking
    X_SAFE = {'move', 'moveq', 'movea', 'movem', 'lea', 'and', 'andi', 'or', 'ori', 'eor', 'eori', 'not',
              'tst', 'cmp', 'cmpi', 'cmpa', 'btst', 'bset', 'bclr', 'st', 'sf', 'scs', 'clr', 'swap', 'ext',
              'exg', 'rol', 'ror', 'bra', 'beq', 'bne', 'bcs', 'bcc', 'jmp'}

    def sets_x(self, o):
        """the translation leaves the 68k X flag equal to the SM83 carry"""
        op = ROM[o]
        if op == 0xCB:
            x, y = ROM[o + 1] >> 6, (ROM[o + 1] >> 3) & 7
            return x == 0 and y in (2, 3, 4, 5, 7)
        if 0x80 <= op < 0xA0 or op in (0xC6, 0xCE, 0xD6, 0xDE): return True
        return op in (0x09, 0x19, 0x29, 0x17, 0x1F, 0x37)

    def x_after(self, o, body, xin):
        if self.sets_x(o): return True
        if 'C' in self.flags_ud(o)[1]: return False
        for b in body:
            if b.endswith(':') or b.startswith(';'): continue
            m = b.split()[0].split('.')[0]
            if m not in self.X_SAFE or 'ccr' in b: return False
        return xin

    # ------------------------------------------------------------------ emission
    def emit_bank(self, bank):
        start, end = bank * 0x4000, (bank + 1) * 0x4000
        offs = sorted(o for o in self.code if start <= o < end)
        lines = [f'; ---- GB bank {bank:02x} (generated by recomp68.py) ----', '\t.text', '\t.68000', '']
        entries = {}
        prev_ft = None           # offset the previous instruction falls through to
        self.floc = 'C'
        self.K = {}
        for o in offs:
            l, t, tgt, kind = self.code[o]
            if prev_ft is not None and prev_ft != o:
                # previous instruction falls through to a non-adjacent instruction
                fl = []
                if self.floc == 'D' and self.live_in.get(prev_ft, ALL): fl.append('move d4,ccr')
                fl.append(f'jmp {label(prev_ft)}' if prev_ft in self.code else 'jmp gb_bad_static')
                lines += ['\t' + x for x in fl]
                self.floc = 'C'
                prev_ft = None
            if prev_ft is None:
                self.floc = 'C'
                self.K = {}
            li = self.live_in[o]
            if o in self.canon:
                if self.floc == 'D' and li:
                    lines.append('\tmove d4,ccr')
                self.floc = 'C'
                self.K = {}
            if o in self.hle:
                # the GB function itself is replaced: jumps into it go to the HAL too
                lines.append(f'{label(o)}:')
                lines.append(f'\tjsr {self.hle[o]}')
                lines.append('\tjmp gb_ret')
                entries[o] = label(o)
                prev_ft = None
                continue
            lab = label(o)
            lines.append(f'{lab}::')
            if self.floc == 'D' and li:
                stub = 's' + lab[1:]
                self.stubs.append(f'{stub}:\tmove sr,d4\n\tjmp {lab}')
                entries[o] = stub
            else:
                entries[o] = lab
            self.lo_now = self.live_out[o]
            self.floc_live_at_target = False
            if o in self.canon or not getattr(self, 'xvalid_ok', False):
                self.xvalid = False
            self.xvalid_ok = True
            try:
                pre = []
                if o in annot.PATCH_BEFORE:
                    self.clobber(pre)
                    pre.append(f'jsr {annot.PATCH_BEFORE[o]}')
                body = pre + self.tr(o)
            except Exception as ex:
                import traceback; traceback.print_exc()
                self.w(o, 'EXCEPTION ' + repr(ex))
                body = ['jsr gb_panic']
            self.kstep(o)
            self.xvalid = self.x_after(o, body, self.xvalid)
            lines.append(f'\t; {addr_of(o):04x}  {t}   ; in {"".join(sorted(li))} out {"".join(sorted(self.lo_now))}')
            for b in body:
                lines.append(b if b.endswith(':') else '\t' + b)
            if not self.lo_now:
                self.floc = 'C'
            if kind in ('jp', 'jr', 'ret') or ROM[o] == 0xE9:
                prev_ft = None
                self.xvalid_ok = False
            else:
                prev_ft = o + l
            if kind == 'call':
                self.floc = 'C'
        if prev_ft is not None:
            lines.append(f'\tjmp {label(prev_ft)}' if prev_ft in self.code else '\tjmp gb_bad_static')
        return lines, entries


def main():
    rc = Recomp()
    rc.daa_done = set()
    rc.liveness()
    rc.canonical_points()
    gen = os.path.join(HERE, 'gen')
    os.makedirs(gen, exist_ok=True)
    banks = sorted({o // 0x4000 for o in rc.code})
    all_entries = {}
    for b in banks:
        lines, entries = rc.emit_bank(b)
        all_entries[b] = entries
        open(os.path.join(gen, f'bank_{b:02x}.s'), 'w').write('\n'.join(lines) + '\n')
    open(os.path.join(gen, 'stubs.s'), 'w').write('\t.text\n\t.68000\n' + '\n'.join(rc.stubs) + '\n')
    # dispatch tables: one long per GB address of the bank's window
    tl = ['; ---- GB address -> translated code (generated by recomp68.py) ----', '\t.data', '\t.long']
    for b in banks:
        ent = all_entries[b]
        base = 0 if b == 0 else 0x4000
        tl.append(f'dtab_{b:02x}::')
        row = []
        for a in range(0x4000):
            o = b * 0x4000 + a
            row.append(ent.get(o, 'gb_bad_target'))
            if len(row) == 8:
                tl.append('\tdc.l ' + ','.join(row)); row = []
    # bank -> table pointer (ROMX tables biased by -$10000 so that (tab, addr*4) works)
    tl.append('bank_dtab::')
    for b in range(64):
        if b in all_entries and b != 0:
            tl.append(f'\tdc.l dtab_{b:02x}-$10000')
        else:
            tl.append('\tdc.l dtab_none-$10000')
    tl.append('dtab_none::')
    tl.append('\tdcb.l 16384,gb_bad_target')
    open(os.path.join(gen, 'tables.s'), 'w').write('\n'.join(tl) + '\n')
    io = ['; ---- IO handler tables $ff00-$ff7f (generated) ----', '\t.text', '\t.long', 'io_rtab::']
    io += [f'\tdc.l {annot.IOR.get(r, "io_r_flat")}' for r in range(0x80)]
    io.append('io_wtab::')
    io += [f'\tdc.l {annot.IOW.get(r, "io_w_flat")}' for r in range(0x80)]
    open(os.path.join(gen, 'iotab.s'), 'w').write('\n'.join(io) + '\n')
    inc = ['; generated'] + [f'\t.include "gen/bank_{b:02x}.s"' for b in banks] + ['\t.include "gen/stubs.s"']
    open(os.path.join(gen, 'code.s'), 'w').write('\n'.join(inc) + '\n')
    open(os.path.join(gen, 'report.txt'), 'w').write('\n'.join(rc.warn) + '\n')
    print('banks:', ' '.join(f'{b:02x}' for b in banks), 'instructions:', len(rc.code),
          'stubs:', len(rc.stubs), 'warnings:', len(rc.warn))


if __name__ == '__main__':
    main()






