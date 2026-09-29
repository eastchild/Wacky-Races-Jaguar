"""wavstat.py FILE.wav : per-second RMS / peak and dominant frequency of a MAME wav"""
import sys, wave, struct, math
import numpy as np
w = wave.open(sys.argv[1])
fs, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
d = np.frombuffer(w.readframes(n), dtype=np.int16).reshape(-1, ch).astype(np.float64)
print('rate', fs, 'channels', ch, 'seconds', n / fs)
for s in range(0, int(n / fs)):
    seg = d[s * fs:(s + 1) * fs]
    rms = np.sqrt((seg ** 2).mean(axis=0))
    pk = np.abs(seg).max(axis=0)
    m = seg.mean(axis=1)
    sp = np.abs(np.fft.rfft(m - m.mean()))
    f = np.argmax(sp) * fs / len(m) if len(m) else 0
    print(f'{s:3d}s rms L{rms[0]:7.0f} R{rms[-1]:7.0f} peak {pk.max():6.0f} main {f:7.1f} Hz')
