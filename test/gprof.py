"""GPU trace profile: cycles per GPU label.
usage: gprof.py trace.log main.lst [frames]  (main.lst: rmac -l listing of main.s)
Labels come from the listing (addresses relative to the section, rebased on gpu_start = $F03000).
Cycle model = MAME's: 1 per instruction, +2 per taken jr/jump (MAME: 4 cycles with its delay slot).
The idle loop (m_wait) is reported apart; with `frames` the totals are divided by it."""
import sys, re, bisect, collections

trace, lst = sys.argv[1], sys.argv[2]
nfr = float(sys.argv[3]) if len(sys.argv) > 3 else 1
labels = []
pending = []
base = None
for line in open(lst, errors='replace'):
    m = re.match(r'\s*\d+\s+([0-9A-F]{8})\s+[0-9A-F]+\s+(\S+?):{1,2}\s', line)
    m2 = re.match(r'\s*\d+\s+([0-9A-F]{8})\s+[0-9A-F]+\s', line)
    ml = re.match(r'\s*\d+\s+(\w+):{1,2}\s*$', line)
    if ml:
        pending.append(ml.group(1))
        continue
    if m2:
        addr = int(m2.group(1), 16)
        names = pending + ([m.group(2)] if m else [])
        pending = []
        for n in names:
            labels.append((addr, n))
            if n == 'gpu_start':
                base = addr
if base is None:
    sys.exit('gpu_start not found in the listing')
end = [a for a, n in labels if n == 'gpu_end_addr']
end = end[0] if end else base + 0x1000
syms = sorted((0xF03000 + a - base, n) for a, n in labels if base <= a < end and not n.startswith('.'))
addrs = [a for a, _ in syms]
ins = collections.Counter()
br = collections.Counter()
rx = re.compile(r'([0-9A-F]{6}): (\w+)')
prev = None          # (pc, label, mnemonic) of the last two instructions
prev2 = None
for line in open(trace):
    m = rx.match(line)
    if not m:
        continue
    pc = int(m.group(1), 16)
    i = bisect.bisect_right(addrs, pc) - 1
    lab = syms[i][1] if i >= 0 else '?'
    ins[lab] += 1
    # taken branch: the instruction after the delay slot is not the next one
    if prev2 and prev2[2] in ('jr', 'jump') and pc != prev[0] + (6 if prev[2] == 'movei' else 2):
        br[prev2[1]] += 1
    prev2, prev = prev, (pc, lab, m.group(2))
idle = ins.get('m_wait', 0) + 2 * br.get('m_wait', 0)
tot = sum(ins.values()) + 2 * sum(br.values())
print(f'cycles {tot / nfr:.0f}  idle {idle / nfr:.0f}  busy {(tot - idle) / nfr:.0f}  '
      f'(instructions {sum(ins.values()) / nfr:.0f}, taken branches {sum(br.values()) / nfr:.0f})')
busy = max(1, tot - idle)
rows = sorted(((ins[n] + 2 * br[n], n) for n in ins if n != 'm_wait'), reverse=True)
for c, n in rows[:45]:
    print(f'{c / nfr:9.0f} {100 * c / busy:5.1f}%  {n:10s} instr {ins[n] / nfr:8.0f}  branches {br[n] / nfr:7.0f}')
