# One frozen-state corpus from MAME: state_<N>.txt (tools/lua/dump_state.lua) and snap_<N>.png for each frame.
#   tools/make_corpus.ps1 -Dir C:\repos\mystwarr-mister\work\ref\play -Frames 300,500,700 -Schedule play [-Machine mystwarr] [-Skip 1]
param(
  [Parameter(Mandatory = $true)][string]$Dir,
  [Parameter(Mandatory = $true)][int[]]$Frames,
  [string]$Schedule = 'none',
  [string]$Machine = 'mystwarr',
  [int]$Skip = 1,
  [hashtable]$ExtraEnv = @{},
  [string[]]$MameArgs = @()
)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dir = [System.IO.Path]::GetFullPath($Dir)
$tmp = Join-Path $Dir '_snap'
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Dir, $tmp | Out-Null
$sorted = $Frames | Sort-Object
$env = @{ DUMPFRAMES = ($sorted -join ','); DUMPDIR = $Dir; SCHEDULE = $Schedule; SKIPBOOT = "$Skip" }
foreach ($k in $ExtraEnv.Keys) { $env[$k] = $ExtraEnv[$k] }
& "$here\mame_run.ps1" -Script dump_state.lua -Machine $Machine -Seconds 7200 -SnapDir $tmp -Env $env -MameArgs $MameArgs | Select-Object -Last 2
$pngs = Get-ChildItem (Join-Path $tmp $Machine) -Filter *.png | Sort-Object Name
if ($pngs.Count -ne $sorted.Count) { Write-Warning "$($pngs.Count) snapshots for $($sorted.Count) frames" }
for ($i = 0; $i -lt [Math]::Min($pngs.Count, $sorted.Count); $i++) {
  Move-Item -Force $pngs[$i].FullName (Join-Path $Dir ("snap_{0}.png" -f $sorted[$i]))
}
Remove-Item -Recurse -Force $tmp
"{0}: {1} frames" -f $Dir, $sorted.Count
