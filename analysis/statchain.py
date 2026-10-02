"""Follow a STAT handler chain (each handler writes the next handler address at $C1A5)
and print each handler's instructions.  statchain.py START [max]"""
import sys, os, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gbdis import ROM, decode

def mem(a):
    return ROM[a] if a < 0x4000 else 0xFF

def handler(a):
    ins = []
    pc = a
    for _ in range(80):
        l, t, tgt, kind = decode(mem, pc)
        ins.append((pc, t))
        pc += l
        if t.startswith(('reti', 'ret', 'jp ', 'jr ')) and 'nz' not in t and ',' not in t.split()[0]:
            if t.startswith(('reti', 'ret')) or t.startswith('jp $') or t.startswith('jr '):
                break
    return ins

def next_of(ins):
    # ld hl,$c1a5 / ld a,$LO / ld (hl+),a / ld (hl),$HI
    for i, (pc, t) in enumerate(ins):
        if t == 'ld hl,$c1a5':
            lo = re.match(r'ld a,\$([0-9a-f]{2})', ins[i + 1][1])
            hi = re.match(r'ld \(hl\),\$([0-9a-f]{2})', ins[i + 3][1])
            if lo and hi:
                return int(hi.group(1), 16) << 8 | int(lo.group(1), 16)
    return None

# ---- classification of the race chain handlers (statchain68.py)
START = 0x1BEC
# handlers with table/branch logic, written by hand (hal/hle.s)
SPECIAL = {0x2242: 'sc_2242', 0x22FF: 'sc_22ff', 0x2209: 'sc_dma'}

def hexv(t, pat):
    m = re.fullmatch(pat, t)
    return int(m.group(1), 16) if m else None

def consts(body, i):
    """OCPS constant writes from body[i]: 'ld a,$SS','ld (hl+),a', 'ld (hl),$VV'... -> [(ocps, [v])]"""
    out = []
    while i < len(body):
        s = hexv(body[i], r'ld a,\$([0-9a-f]{2})')
        if s is not None and body[i + 1] == 'ld (hl+),a':
            vals = []
            i += 2
            while i < len(body) and body[i].startswith('ld (hl),$'):
                vals.append(hexv(body[i], r'ld \(hl\),\$([0-9a-f]{2})'))
                i += 1
            out.append((s, vals))
        else:
            break
    return out, i

def classify(a, body):
    if a in SPECIAL:
        return SPECIAL[a], 0, 0xFF, None
    if body[-1] == 'ret':
        assert body[0] == 'ld hl,$c1a5', body
        return 'sc_last', 0, 0xFF, None
    if body[0] == 'ld hl,$c1a5':
        return 'sc_none', 0, 0xFF, None
    if body[0] == 'ld hl,$c47f':
        assert 'ld a,$90' in body and body.count('ld hl,$ff68') == 1, body
        if body[1] == 'ld l,(hl)':
            assert 'ldh ($ff42),a' in body and 'ld a,($c654)' in body and 'ld a,($c779)' in body
            return 'sc_grad0', 0, 0xFF, None
        off = hexv(body[2], r'add a,\$([0-9a-f]{2})')
        assert body[1] == 'ld a,(hl)' and off is not None, body
        return 'sc_grad', off, 0xFF, None
    if body[:3] == ['ld hl,$ff6a', 'ld a,$aa', 'ld (hl+),a'] and body[3].startswith('ld a,($c1'):
        lo = hexv(body[3], r'ld a,\(\$c1([0-9a-f]{2})\)')
        hi = hexv(body[5], r'ld a,\(\$c1([0-9a-f]{2})\)')
        assert body[4] == 'ld (hl),a' and body[6] == 'ld (hl-),a' and hi == lo + 1, body
        i = 7
        if body[i] == 'ld (hl),$ba' and body[i + 1] == 'ld a,($c529)':
            return 'sc_objrom', lo, 0xFF, None
        cs, i = consts(body, i)
        assert body[i] == 'ld hl,$c1a5', body
        return 'sc_objw', lo, None, cs
    if body[:2] == ['ld hl,$ff6a', 'ld a,$b2'] or body[:2] == ['ld hl,$ff6a', 'ld a,$ba']:
        cs, i = consts(body, 1)
        assert cs and body[i] == 'ld hl,$c1a5', body
        return 'sc_const', 0, None, cs
    raise SystemExit('statchain_gen: unknown handler %04x: %s' % (a, ' | '.join(body)))


if __name__ == '__main__':
    a = int(sys.argv[1], 16)
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    seen = set()
    k = 0
    while a and a not in seen and k < n:
        seen.add(a)
        ins = handler(a)
        nx = next_of(ins)
        body = [t for pc, t in ins if t not in ('push bc', 'pop bc')]
        print('%3d %04x -> %s : %s' % (k, a, ('%04x' % nx) if nx else '----', ' | '.join(body)))
        a = nx
        k += 1
