# run the cartridge headless in MAME with test/probe.lua
#   run.ps1 -Frames "300,600" [-Keys "frame:field:len,..."] [-Watch hexaddr -WatchAt frame]
#           [-TraceAt frame -TraceLen n] [-Prof] [-Logo]
param([string]$Frames = "600", [string]$Out = "", [string]$Keys = "", [string]$Rom = "",
      [string]$Watch = "", [int]$WatchAt = 0, [int]$TraceAt = 0, [int]$TraceLen = 1, [switch]$Prof, [switch]$Logo, [string]$Wav = "")
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ($Rom -eq "") { $Rom = Join-Path $PSScriptRoot "..\build\wacky.j64" }
if ($Out -eq "") { $Out = Join-Path $PSScriptRoot "out" }
New-Item -ItemType Directory -Force $Out | Out-Null
Get-ChildItem $Out -Recurse -File | ForEach-Object { [IO.File]::Delete($_.FullName) }
$env:PROBE_FRAMES = $Frames
$env:PROBE_OUT = $Out
$env:PROBE_INPUT = $Keys
$env:PROBE_WATCH = $Watch
$env:PROBE_WATCH_AT = "$WatchAt"
$env:PROBE_TRACE_AT = "$TraceAt"
$env:PROBE_TRACE_LEN = "$TraceLen"
$env:PROBE_PROF = $(if ($Prof) { "1" } else { "" })
$env:PROBE_LOGO = $(if ($Logo) { "1" } else { "" })
$extra = @(); $snd = @("-sound", "none"); if ($Wav -ne "") { $snd = @("-wavwrite", $Wav) }
if ($TraceAt -gt 0) { $extra = @("-debug", "-debugger", "none") }
$mame = Join-Path $root "tools\mame\mame.exe"
& $mame jaguar -rompath (Join-Path $root "tools\jagroms") -cart $Rom -nothrottle -video none @snd `
    -snapshot_directory $Out -skip_gameinfo @extra -autoboot_script (Join-Path $PSScriptRoot "probe.lua") -autoboot_delay 0 2>&1 |
    Where-Object { $_ -notmatch 'jagwave|EXPECTED|FOUND|might not run|video none|NativeCommandError|^Au caract|^\+|CategoryInfo|^\s*$' }


