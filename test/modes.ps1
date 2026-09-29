# Smoke test of the main menu modes: mode N = N presses of Down on the main menu, then A
# presses through the menus, then accelerate. Reports GB frames, game state (C1A0) and the
# panic record (VARS dbg_buf) at each dump; framebuffers -> test/out_mN/fb0_F.png
param([int[]]$Modes = @(0, 1, 2, 3, 4), [string]$Frames = "4400,5000,6000,7000,8500", [int]$Hold = 5700)
$py = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
foreach ($n in $Modes) {
    $keys = @("3950:P1 B:10")
    for ($d = 0; $d -lt $n; $d++) { $keys += "$(4100 + 40 * $d):P1 Down:8" }
    $keys += (1..7 | ForEach-Object { "$(4010 + 220 * $_):P1 B:10" })
    $keys += "$($Hold):P1 B:3000"
    $out = "$PSScriptRoot\out_m$n"
    & "$PSScriptRoot\run.ps1" -Out $out -Frames $Frames -Keys ($keys -join ',') 2>$null | Out-Null
    foreach ($f in $Frames.Split(',')) {
        $v = [IO.File]::ReadAllBytes("$out\vars_$f.bin")
        $fl = [IO.File]::ReadAllBytes("$out\flat_$f.bin")
        $g = [BitConverter]::ToUInt32(@($v[0x27], $v[0x26], $v[0x25], $v[0x24]), 0)
        $dbg = ($v[0xb4..0xc7] | ForEach-Object { $_.ToString('x2') }) -join ''
        "mode $n frame $f gb $g state $('{0:x2}' -f $fl[0x41a0]) dbg $dbg"
        & $py "$PSScriptRoot\fbview.py" "$out\fb0_$f.bin"
    }
}
