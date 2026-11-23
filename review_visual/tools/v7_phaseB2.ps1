# v7 phase B2: shell branches with corrected sidebar coordinates (physical px).
param([string]$Out = "review_visual\screenshots\v7")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")

$h = (Get-Process cardflow | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowHandle
Set-AppForeground -Handle $h
Set-AppClientSize -Handle $h -Width 2560 -Height 1410 | Out-Null
Start-Sleep -Milliseconds 700
function Shot([string]$name) {
  Park-AppMouse -Handle $h
  $p = Join-Path $Out ("2k_{0}.png" -f $name)
  Save-AppShot -Handle $h -Path $p | Out-Null
  Write-Output "SHOT $p"
}
# Sidebar centers: Колоды 258, ИИ-генерация 326, Конструктор 396,
# Статистика 464, Настройки 534.
Invoke-AppClick -Handle $h -X 180 -Y 464 -DelayMs 1600
Shot "statistics"
Invoke-AppClick -Handle $h -X 180 -Y 534 -DelayMs 1600
Shot "settings"
Invoke-AppClick -Handle $h -X 180 -Y 326 -DelayMs 1600
Shot "generation"
Invoke-AppClick -Handle $h -X 180 -Y 396 -DelayMs 1600
Shot "constructor"
Invoke-AppClick -Handle $h -X 180 -Y 258 -DelayMs 1400
Shot "decks"
