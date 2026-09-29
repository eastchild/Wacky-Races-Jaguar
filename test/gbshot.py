"""gbshot.py SHOTS [KEYS] : reference GB screenshots with PyBoy
SHOTS = "f1,f2,..." (GB frames) -> test/out/gb_F.png
KEYS  = "frame:button:len,..." (button: a b start select up down left right)"""
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
for n in range(1, shots[-1] + 1):
    for f, b, ln in keys:
        if n == f:
            p.button_press(b)
        elif n == f + ln:
            p.button_release(b)
    p.tick(1, n in shots)
    if n in shots:
        p.screen.image.convert('RGB').resize((320, 288), 0).save(os.path.join(HERE, 'out', f'gb_{n}.png'))
p.stop(False)
