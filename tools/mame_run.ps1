# Run MAME 0.289 on a Mystic Warriors set with one of tools/lua/*.lua as the autoboot script.
#   tools/mame_run.ps1 -Script dump_state.lua -Env @{DUMPFRAMES='100,300'; DUMPDIR='C:\...\states'} [-Machine mystwarr] [-Seconds 900]
# MAME and the ROMs are the owner's (see docs/hardware.md "Tools"); the working files go under -Work. Each run starts
# from the EEPROM in <Work>\eeprom.base when there is one (the same contents the system bench is given), so runs repeat.
param(
  [Parameter(Mandatory = $true)][string]$Script,
  [hashtable]$Env = @{},
  [string]$Machine = 'mystwarr',
  [int]$Seconds = 1800,
  [string]$Mame = 'C:\repos\mame0289\mame.exe',
  [string]$RomPath = 'C:\repos\mame0289\roms',
  [string]$Work = 'C:\repos\mw_work\mame',
  [string]$SnapDir = '',
  [string[]]$MameArgs = @()       # more MAME options, e.g. '-joystick_contradictory'
)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$lua = if (Test-Path $Script) { (Resolve-Path $Script).Path } else { Join-Path $here "lua\$Script" }
New-Item -ItemType Directory -Force "$Work\cfg", "$Work\nvram\$Machine" | Out-Null
if (Test-Path "$Work\eeprom.base") { Copy-Item -Force "$Work\eeprom.base" "$Work\nvram\$Machine\eeprom" }
if (-not $SnapDir) { $SnapDir = "$Work\snap" }
New-Item -ItemType Directory -Force $SnapDir | Out-Null
if (-not $Env.ContainsKey('SKIPBOOT_FILE')) { $Env['SKIPBOOT_FILE'] = (Join-Path $here 'skipboot.txt') }
foreach ($k in $Env.Keys) { Set-Item -Path "Env:$k" -Value ([string]$Env[$k]) }
try {
  & $Mame $Machine -rompath $RomPath -video none -sound none -nothrottle -skip_gameinfo -window `
    -cfg_directory "$Work\cfg" -nvram_directory "$Work\nvram" -snapshot_directory $SnapDir `
    -autoboot_script $lua -seconds_to_run $Seconds @MameArgs 2>&1 | Select-Object -Last 5
} finally {
  foreach ($k in $Env.Keys) { Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue }
}
