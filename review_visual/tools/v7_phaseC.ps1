# v7 phase C: shell branches from the decks shell (sidebar visible).
param([string]$Out = "review_visual\screenshots\v7")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")

$h = (Get-Process cardflow | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowHandle
Set-AppForeground -Handle $h
Set-AppClientSize -Handle $h -Width 2560 -Height 1410 | Out-Null
Start-Sleep -Milliseconds 800
function Shot([string]$name) {
  Park-AppMouse -Handle $h
  $p = Join-Path $Out ("2k_{0}.png" -f $name)
  Save-AppShot -Handle $h -Path $p | Out-Null
  Write-Output "SHOT $p"
}
# Статистика
Invoke-AppClick -Handle $h -X 180 -Y 464 -DelayMs 1800
Shot "statistics"
# Настройки
Invoke-AppClick -Handle $h -X 180 -Y 533 -DelayMs 1800
Shot "settings"
# Конструктор (sub-page)
Invoke-AppClick -Handle $h -X 180 -Y 397 -DelayMs 1800
Shot "constructor"
# Назад в оболочку и «Колоды»
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1200
Invoke-AppClick -Handle $h -X 180 -Y 258 -DelayMs 1400
Shot "decks"
# ИИ-генерация (sub-page)
Invoke-AppClick -Handle $h -X 180 -Y 327 -DelayMs 1800
Shot "generation"
# Назад
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1200
Shot "decks_after"
