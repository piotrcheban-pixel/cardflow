# v7 phase B: shell branches at 2560x1410 (client physical px, DPR 1.5).
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

# Back to the shell (sub-page back arrow).
Invoke-AppClick -Handle $h -X 41 -Y 50 -DelayMs 1200
Shot "decks"

# Sidebar: Статистика (y=502), Настройки (y=570), ИИ-генерация (y=345), Конструктор (y=422)
Invoke-AppClick -Handle $h -X 180 -Y 502 -DelayMs 1600
Shot "statistics"

Invoke-AppClick -Handle $h -X 180 -Y 570 -DelayMs 1600
Shot "settings"

Invoke-AppClick -Handle $h -X 180 -Y 345 -DelayMs 1600
Shot "generation"

Invoke-AppClick -Handle $h -X 180 -Y 422 -DelayMs 1600
Shot "constructor"

Invoke-AppClick -Handle $h -X 180 -Y 262 -DelayMs 1400
Shot "decks2"
