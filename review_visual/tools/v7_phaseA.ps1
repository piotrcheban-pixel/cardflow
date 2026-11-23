# v7 phase A: navigation reconnaissance at 2560x1410 client (DPR 1.5 -> 1707x940 logical).
param([string]$Out = "review_visual\screenshots\v7")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")

$h = (Get-Process cardflow | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowHandle
Set-AppForeground -Handle $h
New-Item -ItemType Directory -Force -Path $Out | Out-Null
function Shot([string]$name) {
  Park-AppMouse -Handle $h
  $p = Join-Path $Out ("2k_{0}.png" -f $name)
  Save-AppShot -Handle $h -Path $p | Out-Null
  Write-Output "SHOT $p"
}

Set-AppClientSize -Handle $h -Width 2560 -Height 1410 | Out-Null
Start-Sleep -Milliseconds 900
Shot "decks"

# 1. Search filter: sidebar search field, type deck name fragment.
Invoke-AppClick -Handle $h -X 150 -Y 95 -DelayMs 400
Send-AppText -Handle $h -Text "цуа" -DelayMs 900
Shot "decks_search"

# 2. Open the first filtered deck card by its title.
Invoke-AppClick -Handle $h -X 560 -Y 530 -DelayMs 1400
Shot "deck"

# 3. Start-session panel opens the modes sheet.
Invoke-AppClick -Handle $h -X 1280 -Y 460 -DelayMs 900
Shot "modes_sheet"
