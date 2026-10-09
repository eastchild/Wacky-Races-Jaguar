"""Build the Jaguar cartridge:  python build.py [--norecomp] [--analyze] [--hud] [--diag]

    analysis/gbre.py -> build/analysis/analysis.pkl (disassembly of the GB ROM seeded with the
    coverage in analysis/coverage; only when missing, or with --analyze) ;
    recomp68.py + statchain68.py -> gen/*.s ; rmac main.s ; rln (text at $4000, data at $A00000) ;
    rmac/rln boot.s ; ROM = Univ.bin header + boot stub ($802000) + program image ($802100)
    + data (dispatch tables, GB ROM) at $A00000.
Needs: Python 3, JagStudio's rmac, rln, include/JAGUAR.INC and include/Univ.bin (JAGSTUDIO = its
"buildfiles" directory, default D:\\source_codes\\jagstudio\\buildfiles), and the original GB ROM
(see analysis/gbrom.py: this directory, its parent, or WACKY_GBROM).
Output: build/wacky.j64, copied to <parent>/output/Wacky Races (Jaguar).j64 (WACKY_OUTPUT: another
directory ; --hud: ... [debug HUD].j64).
--sync: deterministic test build (test/sync.ps1); --alldraw / --nodraw / --nogpuline: measurements.
"""
import os, sys, subprocess, shutil, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, 'analysis'))
import gbrom

JS = os.environ.get('JAGSTUDIO', r'D:\source_codes\jagstudio\buildfiles')
EXE = '.exe' if os.name == 'nt' else ''
RMAC = os.path.join(JS, 'bin', 'rmac' + EXE)
RLN = os.path.join(JS, 'bin', 'rln' + EXE)
INC = os.path.join(JS, 'include')
BUILD = os.path.join(HERE, 'build')
OUTPUT = os.environ.get('WACKY_OUTPUT', os.path.join(ROOT, 'output'))
TEXT_ADDR = 0x4000
DATA_ADDR = 0xA00000
ROM_BASE = 0x800000
ROM_SIZE = 0x400000
# test / measurement builds: they stay in build/
TEST_FLAGS = ('--sync', '--alldraw', '--nodraw', '--nogpuline', '--profile')


def run(cmd, log):
    r = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True)
    out = (r.stdout or '') + (r.stderr or '')
    open(os.path.join(BUILD, log), 'w').write(out)
    errs = [l for l in out.splitlines() if re.search(r'error|Error|undefined|Undefined', l)]
    if r.returncode != 0 or errs:
        print('\n'.join(errs[:60]) or out[-3000:])
        raise SystemExit(f'{cmd[0]} failed ({log})')
    return out


def main():
    os.makedirs(BUILD, exist_ok=True)
    py = sys.executable
    for f in (RMAC, RLN, os.path.join(INC, 'JAGUAR.INC'), os.path.join(INC, 'Univ.bin')):
        if not os.path.isfile(f):
            raise SystemExit(f'{f} not found: set JAGSTUDIO to the JagStudio "buildfiles" directory')
    GBROM = gbrom.path()
    if '--norecomp' not in sys.argv:
        pkl = os.path.join(BUILD, 'analysis', 'analysis.pkl')
        if '--analyze' in sys.argv or not os.path.exists(pkl):
            print('analysis of the GB ROM (analysis/gbre.py)...')
            subprocess.run([py, os.path.join(HERE, 'analysis', 'gbre.py'), os.path.join(HERE, 'analysis', 'coverage')],
                           cwd=HERE, check=True, stdout=subprocess.DEVNULL,
                           env=dict(os.environ, GBRE_OUT=os.path.join(BUILD, 'analysis')))
        subprocess.run([py, os.path.join(HERE, 'recomp68.py')], cwd=HERE, check=True)
        subprocess.run([py, os.path.join(HERE, 'statchain68.py')], cwd=HERE, check=True)
    shutil.copyfile(GBROM, os.path.join(BUILD, 'gbrom.bin'))
    defs = (['-dPROFILE=1'] if '--profile' in sys.argv else []) + (['-dHUD=1'] if '--hud' in sys.argv else []) + (['-dDIAG=1'] if '--diag' in sys.argv else []) \
        + (['-dALLDRAW=1'] if '--alldraw' in sys.argv else []) + (['-dALLDRAW=2'] if '--nodraw' in sys.argv else []) \
        + (['-dNOGPULINE=1'] if '--nogpuline' in sys.argv else []) + (['-dALLDRAW=3'] if '--sync' in sys.argv else [])
    run([RMAC, '-fb', '-i' + INC] + defs + ['-o', 'build/main.o', 'main.s'], 'rmac_main.log')
    mp = run([RLN, '-z', '-n', '-m', '-a', '%x' % TEXT_ADDR, '%x' % DATA_ADDR, 'x', '-o', 'build/main.bin',
              'build/main.o'], 'rln_main.log')
    run([RMAC, '-fb', '-o', 'build/boot.o', 'boot.s'], 'rmac_boot.log')
    run([RLN, '-z', '-n', '-a', '802000', 'x', 'x', '-o', 'build/boot.bin', 'build/boot.o'], 'rln_boot.log')
    syms = symbols(mp)
    img = open(os.path.join(BUILD, 'main.bin'), 'rb').read()
    text_len = syms['_TEXT_E'] - TEXT_ADDR
    data_len = syms['_DATA_E'] - DATA_ADDR
    assert len(img) == text_len + data_len, (len(img), text_len, data_len)
    boot = bytearray(open(os.path.join(BUILD, 'boot.bin'), 'rb').read())
    assert len(boot) <= 0x100
    boot[-4:] = text_len.to_bytes(4, 'big')           # img_size
    rom = bytearray(b'\xff' * ROM_SIZE)
    univ = open(os.path.join(INC, 'Univ.bin'), 'rb').read()
    rom[0:len(univ)] = univ
    rom[0x2000:0x2000 + len(boot)] = boot
    rom[0x2100:0x2100 + text_len] = img[:text_len]
    assert 0x2100 + text_len <= DATA_ADDR - ROM_BASE
    d0 = DATA_ADDR - ROM_BASE
    rom[d0:d0 + data_len] = img[text_len:]
    out = os.path.join(BUILD, 'wacky.j64')
    open(out, 'wb').write(rom)
    # the debug HUD build has its own name
    if not any(f in sys.argv for f in TEST_FLAGS):
        name = 'Wacky Races (Jaguar) [debug HUD].j64' if '--hud' in sys.argv else 'Wacky Races (Jaguar).j64'
        if '--diag' in sys.argv:          # real hardware boot diagnostic (stage colours)
            name = name.replace('(Jaguar)', '(Jaguar) [diag]')
        os.makedirs(OUTPUT, exist_ok=True)
        shutil.copyfile(out, os.path.join(OUTPUT, name))
    open(os.path.join(BUILD, 'symbols.txt'), 'w').write(
        '\n'.join(f'{v:08x} {k}' for k, v in sorted(syms.items(), key=lambda kv: kv[1])) + '\n')
    print(f'text {text_len} bytes (${TEXT_ADDR:x}-${TEXT_ADDR + text_len:x}), data {data_len} bytes -> {out}')


def symbols(mapout):
    return {m.group(1): int(m.group(2), 16) for m in re.finditer(r'(\S+)\s+G\s+([0-9A-Fa-f]{8})', mapout)}


if __name__ == '__main__':
    main()
