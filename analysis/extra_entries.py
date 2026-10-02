"""Code entries reachable only through data tables (never seen in the coverage traces).
Writes extra_entries.txt ("offset bank" lines) read by gbre.py (kept in the repository: run it
again after gbre.py when the coverage or the decoding rules change).

- game state handlers: 0:3DB8 increments C1A0 and reads the state script pointer from the
  word table at 31:5D6A; 0:3E02 walks the script records (bank, src, sel, [len,] dst; $FF ends)
  and 0:3DF6 jumps (push/ret) to the bank-0 handler word that follows.
  The words after the handler are its parameters (see the STAT handler case below).
- bank 6 menus: jp (hl) at 6:4446 (item handler word before each item record).
- cheat codes: 1:7126 walks records at 1:724D (count, then 7 letters + handler word), jp (hl).
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gbdis import ROM


def off(bank, a):
    return a if a < 0x4000 else bank * 0x4000 + a - 0x4000


def rd(bank, a):
    return ROM[off(bank, a)]


def rw(bank, a):
    return rd(bank, a) | rd(bank, a + 1) << 8


out = []
# game states
handlers, stat = set(), set()
for i in range(256):
    p = rw(0x31, 0x5D6A + 2 * i)
    if p == 0:
        continue
    if not (0x5E88 <= p < 0x8000):
        break
    a, n, ok = p, 0, True
    while True:
        b = rd(0x31, a); a += 1
        if b == 0xFF:
            break
        if b > 0x3F or n > 40:
            ok = False
            break
        a += 3
        a += 4 if rd(0x31, a + 1) < 0x80 else 2
        n += 1
    if not ok:
        break
    h = rw(0x31, a)
    handlers.add(h)
    # handlers starting with call 3D84 / call 1BD7 take (music, table, STAT handler) words:
    # 1BD7 -> 1:66E2 installs the third one as the STAT handler (jp at C1A4)
    if bytes(ROM[h:h + 6]) == b'\xcd\x84\x3d\xcd\xd7\x1b':
        stat.add(rw(0x31, a + 6))
for h in sorted(handlers):
    out.append(f'{h:06x} 31   # game state handler')
for h in sorted(stat):
    out.append(f'{h:06x} 01   # STAT handler installed by a game state')
# cheat codes
n = rd(1, 0x724D)
for i in range(n):
    h = rw(1, 0x724D + 1 + 9 * i + 7)
    out.append(f'{off(1, h):06x} 01   # cheat code {i}')
# bank 6 menus (jp (hl) at 6:4446): (CAEB) -> [count][item pointers], the handler word sits
# just before each item record. Tables validated by a known handler or 'ld a,n' handlers.
known = set()
p = os.path.join(HERE, '..', 'build', 'analysis', 'analysis.pkl')
if os.path.exists(p):
    import pickle
    known = set(pickle.load(open(p, 'rb'))['code'])
for t in range(0x4001, 0x7FF0):
    n = rd(6, t - 1)
    if not (2 <= n <= 20) or t + 2 * n > 0x8000:
        continue
    ps = [rw(6, t + 2 * i) for i in range(n)]
    if not all(0x4002 <= q < 0x8000 for q in ps):
        continue
    hs = [rw(6, q - 2) for q in ps]
    if not all(0x4000 <= h < 0x8000 for h in hs):
        continue
    if not (any(off(6, h) in known for h in hs) or all(rd(6, h) == 0x3E for h in hs)):
        continue
    for h in hs:
        out.append(f'{off(6, h):06x} 06   # menu item handler (table 6:{t:04x})')
# animation nodes run by 1:6A23 (push/ret at 1:6A44): node = [dw next][limit byte][code],
# the object points at the limit byte, code at limit+1; follow the next chains from the
# targets seen in the traces
seen = set()
for d in ['coverage']:
    p = os.path.join(HERE, d, 'rettargets.txt')
    if os.path.exists(p):
        for ln in open(p):
            a, _, b = ln.split()
            if int(a, 16) == off(1, 0x6A44):
                seen.add(int(b, 16))
todo, nodes = [0x4000 + t % 0x4000 for t in seen], set()
while todo:
    c = todo.pop()
    if c in nodes or not (0x4003 <= c < 0x8000):
        continue
    nodes.add(c)
    nxt = rw(1, c - 3)
    if 0x4000 <= nxt < 0x7FFF:
        todo.append(nxt + 1)
for c in sorted(nodes):
    if off(1, c) not in seen:
        out.append(f'{off(1, c):06x} 01   # animation node')
open(os.path.join(HERE, 'extra_entries.txt'), 'w').write('\n'.join(out) + '\n')
print(len(out), 'entries')
