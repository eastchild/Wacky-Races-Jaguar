"""gbhooks.py FROM TO KEYS "bank:addr,..." : print LY (and IF/IE/STAT) each time PyBoy executes
the given GB addresses between GB frames FROM and TO"""
import sys, os
from pyboy import PyBoy
HERE = os.path.dirname(os.path.abspath(__file__))
ROM = os.path.join(HERE, '..', '..', 'Wacky Races (Europe) (En,Fr,De,Es,It,Nl).gbc')
f0, f1 = int(sys.argv[1]), int(sys.argv[2])
keys = []
for k in sys.argv[3].split(','):
    if k:
        f, b, n = k.split(':')
        keys.append((int(f), b, int(n)))
p = PyBoy(ROM, window='null', sound_emulated=False)
p.set_emulation_speed(0)
state = {'n': 0}


def cb(tag):
    if f0 <= state['n'] <= f1:
        m = p.memory
        print(f"frame {state['n']} {tag} LY={m[0xFF44]} STAT={m[0xFF41]:02x} IF={m[0xFF0F]:02x} IE={m[0xFFFF]:02x} C1A5={m[0xC1A6]:02x}{m[0xC1A5]:02x}")


for spec in sys.argv[4].split(','):
    b, a = spec.split(':')
    p.hook_register(int(b, 16), int(a, 16), cb, f'{b}:{a}')
for n in range(1, f1 + 1):
    state['n'] = n
    for f, b, ln in keys:
        if n == f:
            p.button_press(b)
        elif n == f + ln:
            p.button_release(b)
    p.tick(1, False)
p.stop(False)
