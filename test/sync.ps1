# Deterministic frame dumps of a `build.py --sync` ROM: every GB frame is drawn, the GPU finishes
# it before the next one starts and the joypad follows a schedule in GB frames, so the picture of
# frame N does not depend on the speed of the 68000 or of the GPU. Used to check that a change of
# the renderer / of the HAL leaves every picture identical:
#   build.py --sync ; test\sync.ps1 -Out test\gold        (reference)
#   ... change ... ; build.py --sync ; test\sync.ps1 -Out test\out ; python test\fbcmp.py test\gold test\out
# -Mode N: N presses of Down on the main menu (other game modes).
param([string]$Out = "", [string]$Frames = "", [string]$Keys = "", [int]$Mode = 0, [int]$Last = 9000, [string]$Rom = "")
if (-not $Keys) {
    $k = @("3730:P1 B:10")
    for ($d = 0; $d -lt $Mode; $d++) { $k += "$(3860 + 40 * $d):P1 Down:8" }
    $k += (1..7 | ForEach-Object { "$(3730 + 220 * $_):P1 B:10" })
    $k += "5380:P1 B:9000"
    $k += (0..40 | ForEach-Object { "$(5480 + 90 * $_):P1 A:6" })
    $k += (0..30 | ForEach-Object { "$(5700 + 130 * $_):P1 $(if ($_ % 2) { 'Left' } else { 'Right' }):50" })
    $Keys = $k -join ','
}
if (-not $Frames) {
    $f = @(); for ($i = 200; $i -le $Last; $i += 40) { $f += $i }
    $f += 5600..5620; $f += 7500..7510
    $Frames = ($f | Where-Object { $_ -le $Last } | Sort-Object -Unique) -join ','
}
$runArgs = @{ Frames = $Frames; Keys = $Keys }
if ($Out) { $runArgs.Out = $Out }
if ($Rom) { $runArgs.Rom = $Rom }
$env:PROBE_SYNC = "1"
& "$PSScriptRoot\run.ps1" @runArgs
$env:PROBE_SYNC = $null
