"""gbsound.py FRAMES OUT.wav : reference GB audio with PyBoy (no input)"""
import sys, wave, os
import numpy as np
from pyboy import PyBoy
ROM = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'Wacky Races (Europe) (En,Fr,De,Es,It,Nl).gbc')
p = PyBoy(ROM, window='null', sound_emulated=True)
p.set_emulation_speed(0)
chunks = []
for i in range(int(sys.argv[1])):
    p.tick(1, False, True)
    chunks.append(p.sound.ndarray.copy())
a = np.concatenate(chunks)
fs = p.sound.sample_rate
print('samples', a.shape, a.dtype, 'rate', fs)
if a.dtype != np.int16:
    a = (a.astype(np.float64) / max(1, np.abs(a).max()) * 20000).astype(np.int16)
w = wave.open(sys.argv[2], 'wb')
w.setnchannels(a.shape[1] if a.ndim > 1 else 1)
w.setsampwidth(2)
w.setframerate(fs)
w.writeframes(a.tobytes())
w.close()
p.stop(False)
