# Frame rate per screen, windows in GB frames (PROBE_GBTIME): game frames/s, drawn frames/s and
# 68k waits (GPU log full, VBlank pacing) per game frame.
# Usage: test\fps.ps1 [-Rom file] [-Windows "a-b,c-d"] [-Names "x,y"] [-Keys ...]
param([string]$Rom = "", [string]$Windows = "900-1200,3300-3600,4020-4140,5600-5900",
      [string]$Names = "intro,language,racer select,race", [string]$Keys = "")
if (-not $Keys) {
    $Keys = ((0..7 | ForEach-Object { "$(3730 + 220 * $_):P1 B:10" }) + "5380:P1 B:3000") -join ','
}
$frames = @()
foreach ($w in $Windows.Split(',')) { $a, $b = $w.Split('-'); $frames += [int]$a; $frames += [int]$b }
$fr = ($frames | Sort-Object -Unique) -join ','
$runArgs = @{ Frames = $fr; Keys = $Keys }
if ($Rom) { $runArgs.Rom = $Rom }
$env:PROBE_GBTIME = "1"
& "$PSScriptRoot\run.ps1" @runArgs 2>$null | Out-Null
$env:PROBE_GBTIME = $null
$py = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$root = $PSScriptRoot -replace '\\', '/'
& $py -c @"
import struct
names='$Names'.split(',')
def st(f):
    v=open(f'$root/out/vars_{f}.bin','rb').read()
    r=dict(l.strip().split('=') for l in open(f'$root/out/regs_{f}.txt') if '=' in l)
    L=lambda o: struct.unpack('>I',v[o:o+4])[0]
    return L(0x24), int(r['f03fec'],16), L(0xfc), L(0x100), L(0x1c)
for i,w in enumerate('$Windows'.split(',')):
    a,b=map(int,w.split('-'))
    (g0,d0,wg0,wv0,v0),(g1,d1,wg1,wv1,v1)=st(a),st(b)
    n=max(1,v1-v0); g=max(1,g1-g0)
    print(f'{names[i] if i<len(names) else w:13s} game {60*(g1-g0)/n:5.1f}/s  drawn {60*(d1-d0)/n:5.1f}/s  '
          f'wait GPU {(wg1-wg0)/g:6.0f}  wait VBL {(wv1-wv0)/g:6.0f}  (per game frame)')
"@
