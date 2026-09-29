"""gbstate.py FRAMES KEYS : compare PyBoy GB state with MAME dumps test/out/flat_F.bin
(WRAM0 $C000-$CFFF, OAM, IO $FF40-$FF4B, HRAM) at the given GB frames"""
import sys, os
from pyboy import PyBoy
HERE = os.path.dirname(os.path.abspath(__file__))
ROM = os.path.join(HERE, '..', '..', 'Wacky Races (Europe) (En,Fr,De,Es,It,Nl).gbc')
shots = sorted(int(x) for x in sys.argv[1].split(','))
keys = []
if len(sys.argv) > 2 and sys.argv[2]:
    for k in sys.argv[2].split(','):
        f, b, n = k.split(':')
        keys.append((int(f), b, int(n)))
p = PyBoy(ROM, window='null', sound_emulated=False)
p.set_emulation_speed(0)
AREAS = [('WRAM0', 0xC000, 0x1000), ('OAM', 0xFE00, 0xA0), ('IO', 0xFF40, 0x0C), ('HRAM', 0xFF80, 0x7F)]
for n in range(1, shots[-1] + 1):
    for f, b, ln in keys:
        if n == f:
            p.button_press(b)
        elif n == f + ln:
            p.button_release(b)
    p.tick(1, False)
    if n in shots:
        fl = open(os.path.join(HERE, 'out', f'flat_{n}.bin'), 'rb').read()
        print(f'== frame {n}')
        for name, a, ln in AREAS:
            gb = bytes(p.memory[a:a + ln])
            jg = fl[a - 0x8000:a - 0x8000 + ln]
            diff = [i for i in range(ln) if gb[i] != jg[i] and not (0xC000 <= a + i < 0xC100)]
            print(f'{name}: {len(diff)} diffs', ' '.join(f'{a+i:04x}:{gb[i]:02x}/{jg[i]:02x}' for i in diff[:24]))
p.stop(False)
