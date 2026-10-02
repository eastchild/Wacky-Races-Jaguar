"""SM83 disassembler.  gbdis.py BANK:ADDR [count]   (BANK hex, ADDR hex)"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gbrom
ROM = gbrom.load()           # the original ROM


R = ['b', 'c', 'd', 'e', 'h', 'l', '(hl)', 'a']
RP = ['bc', 'de', 'hl', 'sp']
RP2 = ['bc', 'de', 'hl', 'af']
CC = ['nz', 'z', 'nc', 'c']
ALU = ['add a,', 'adc a,', 'sub ', 'sbc a,', 'and ', 'xor ', 'or ', 'cp ']
ROT = ['rlc', 'rrc', 'rl', 'rr', 'sla', 'sra', 'swap', 'srl']

def decode(mem, pc):
    """mem: callable addr->byte. returns (length, text, target or None, kind)"""
    op = mem(pc)
    n = lambda: mem(pc + 1)
    nn = lambda: mem(pc + 1) | mem(pc + 2) << 8
    e = lambda: (pc + 2 + ((mem(pc + 1) ^ 0x80) - 0x80)) & 0xFFFF
    x, y, z, p, q = op >> 6, (op >> 3) & 7, op & 7, (op >> 4) & 3, (op >> 3) & 1
    if op == 0xCB:
        o = mem(pc + 1); xx, yy, zz = o >> 6, (o >> 3) & 7, o & 7
        if xx == 0: return 2, f'{ROT[yy]} {R[zz]}', None, ''
        return 2, f"{['', 'bit', 'res', 'set'][xx]} {yy},{R[zz]}", None, ''
    if x == 1:
        if op == 0x76: return 1, 'halt', None, ''
        return 1, f'ld {R[y]},{R[z]}', None, ''
    if x == 2: return 1, f'{ALU[y]}{R[z]}', None, ''
    T = {
        0x00: (1, 'nop'), 0x08: (3, 'ld (${nn:04x}),sp'), 0x10: (2, 'stop'),
        0x07: (1, 'rlca'), 0x0F: (1, 'rrca'), 0x17: (1, 'rla'), 0x1F: (1, 'rra'),
        0x27: (1, 'daa'), 0x2F: (1, 'cpl'), 0x37: (1, 'scf'), 0x3F: (1, 'ccf'),
        0x02: (1, 'ld (bc),a'), 0x12: (1, 'ld (de),a'), 0x22: (1, 'ld (hl+),a'), 0x32: (1, 'ld (hl-),a'),
        0x0A: (1, 'ld a,(bc)'), 0x1A: (1, 'ld a,(de)'), 0x2A: (1, 'ld a,(hl+)'), 0x3A: (1, 'ld a,(hl-)'),
        0xE0: (2, 'ldh ($ff{n:02x}),a'), 0xF0: (2, 'ldh a,($ff{n:02x})'), 0xE2: (1, 'ld ($ff00+c),a'), 0xF2: (1, 'ld a,($ff00+c)'),
        0xEA: (3, 'ld (${nn:04x}),a'), 0xFA: (3, 'ld a,(${nn:04x})'), 0xE8: (2, 'add sp,{sn}'), 0xF8: (2, 'ld hl,sp+{sn}'),
        0xF9: (1, 'ld sp,hl'), 0xF3: (1, 'di'), 0xFB: (1, 'ei'), 0xE9: (1, 'jp (hl)'),
        0xC9: (1, 'ret'), 0xD9: (1, 'reti'),
    }
    if op in T:
        l, t = T[op]
        v = {'n': n() if l > 1 else 0, 'nn': nn() if l > 2 else 0, 'sn': ((n() ^ 0x80) - 0x80) if l > 1 else 0}
        kind = 'ret' if op in (0xC9, 0xD9) else 'jphl' if op == 0xE9 else ''
        return l, t.format(**v), None, kind
    if x == 0:
        if z == 0:
            if op == 0x18: return 2, f'jr ${e():04x}', e(), 'jr'
            return 2, f'jr {CC[y-4]},${e():04x}', e(), 'jrc'
        if z == 1:
            if q == 0: return 3, f'ld {RP[p]},${nn():04x}', None, ''
            return 1, f'add hl,{RP[p]}', None, ''
        if z == 3: return 1, f"{'inc' if q == 0 else 'dec'} {RP[p]}", None, ''
        if z == 4: return 1, f'inc {R[y]}', None, ''
        if z == 5: return 1, f'dec {R[y]}', None, ''
        if z == 6: return 2, f'ld {R[y]},${n():02x}', None, ''
    if x == 3:
        if z == 0: return 1, f'ret {CC[y]}', None, 'retc'
        if z == 1: return 1, f'pop {RP2[p]}', None, ''
        if z == 2: return 3, f'jp {CC[y]},${nn():04x}', nn(), 'jpc'
        if op == 0xC3: return 3, f'jp ${nn():04x}', nn(), 'jp'
        if z == 4: return 3, f'call {CC[y]},${nn():04x}', nn(), 'call'
        if z == 5:
            if op == 0xCD: return 3, f'call ${nn():04x}', nn(), 'call'
            return 1, f'push {RP2[p]}', None, ''
        if z == 6: return 2, f'{ALU[y]}${n():02x}', None, ''
        if z == 7: return 1, f'rst ${y*8:02x}', y * 8, 'call'
    return 1, f'db ${op:02x} ; ILLEGAL', None, ''

def rom_mem(bank):
    def m(a):
        a &= 0xFFFF
        if a < 0x4000: return ROM[a]
        if a < 0x8000: return ROM[bank * 0x4000 + a - 0x4000]
        return 0
    return m

if __name__ == '__main__':
    bank, addr = sys.argv[1].split(':')
    bank, addr = int(bank, 16), int(addr, 16)
    cnt = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    m = rom_mem(bank)
    pc = addr
    for _ in range(cnt):
        l, t, tgt, k = decode(m, pc)
        bs = ' '.join(f'{m(pc+i):02x}' for i in range(l))
        print(f'{bank:02x}:{pc:04x}  {bs:<9} {t}')
        pc += l
