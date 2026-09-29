"""gbmem.py FRAMES KEYS ADDR LEN : PyBoy memory bytes at GB frames (vs test/out/flat_F.bin if present)"""
import sys, os
from pyboy import PyBoy
HERE = os.path.dirname(os.path.abspath(__file__))
ROM = os.path.join(HERE, '..', '..', 'Wacky Races (Europe) (En,Fr,De,Es,It,Nl).gbc')
shots = sorted(int(x) for x in sys.argv[1].split(','))
keys = []
for k in sys.argv[2].split(','):
    if k:
        f, b, n = k.split(':')
        keys.append((int(f), b, int(n)))
addr, ln = int(sys.argv[3], 16), int(sys.argv[4])
p = PyBoy(ROM, window='null', sound_emulated=False)
p.set_emulation_speed(0)
for n in range(1, shots[-1] + 1):
    for f, b, l in keys:
        if n == f:
            p.button_press(b)
        elif n == f + l:
            p.button_release(b)
    p.tick(1, False)
    if n in shots:
        gb = bytes(p.memory[addr:addr + ln])
        line = f'{n} GB  {gb.hex(" ")}'
        fp = os.path.join(HERE, 'out', f'flat_{n}.bin')
        if os.path.exists(fp):
            fl = open(fp, 'rb').read()
            line += f'\n{n} JAG {fl[addr - 0x8000:addr - 0x8000 + ln].hex(" ")}'
        print(line)
p.stop(False)
