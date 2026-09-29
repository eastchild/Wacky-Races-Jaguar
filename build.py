"""Build the Jaguar cartridge:  python build.py [--norecomp]

    recomp68.py -> gen/*.s ; rmac main.s ; rln (text at $4000, data at $A00000) ;
    rmac/rln boot.s ; ROM = Univ.bin header + boot stub ($802000) + program image ($802100)
    + data (dispatch tables, GB ROM) at $A00000.
Output: build/wacky.j64 and <root>/output/Wacky Races (Jaguar).j64
"""
import os, sys, subprocess, shutil, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
JS = r'D:\source_codes\jagstudio\buildfiles'
RMAC = os.path.join(JS, 'bin', 'rmac.exe')
RLN = os.path.join(JS, 'bin', 'rln.exe')
INC = os.path.join(JS, 'include')
GBROM = os.path.join(ROOT, 'Wacky Races (Europe) (En,Fr,De,Es,It,Nl).gbc')
BUILD = os.path.join(HERE, 'build')
TEXT_ADDR = 0x4000
DATA_ADDR = 0xA00000
ROM_BASE = 0x800000
ROM_SIZE = 0x400000


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
    if '--norecomp' not in sys.argv:
        subprocess.run([py, os.path.join(HERE, 'recomp68.py')], cwd=HERE, check=True)
        subprocess.run([py, os.path.join(HERE, 'statchain68.py')], cwd=HERE, check=True)
    shutil.copyfile(GBROM, os.path.join(BUILD, 'gbrom.bin'))
    run([RMAC, '-fb', '-i' + INC] + (['-dPROFILE=1'] if '--profile' in sys.argv else []) + (['-dHUD=1'] if '--hud' in sys.argv else []) + (['-dALLDRAW=1'] if '--alldraw' in sys.argv else []) + (['-dALLDRAW=2'] if '--nodraw' in sys.argv else []) + (['-dNOGPULINE=1'] if '--nogpuline' in sys.argv else []) +['-o', 'build/main.o', 'main.s'], 'rmac_main.log')
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
    os.makedirs(os.path.join(ROOT, 'output'), exist_ok=True)
    shutil.copyfile(out, os.path.join(ROOT, 'output', 'Wacky Races (Jaguar).j64'))
    open(os.path.join(BUILD, 'symbols.txt'), 'w').write(
        '\n'.join(f'{v:08x} {k}' for k, v in sorted(syms.items(), key=lambda kv: kv[1])) + '\n')
    print(f'text {text_len} bytes (${TEXT_ADDR:x}-${TEXT_ADDR + text_len:x}), data {data_len} bytes -> {out}')


def symbols(mapout):
    return {m.group(1): int(m.group(2), 16) for m in re.finditer(r'(\S+)\s+G\s+([0-9A-Fa-f]{8})', mapout)}

if __name__ == '__main__':
    main()






