# Сценарий 2: назад к колодам → Статистика → Настройки → ИИ-генерация → Конструктор.
param([string]$Out = "review_visual\screenshots")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")

$h = (Get-Process cardflow | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowHandle
Set-AppForeground -Handle $h
Set-AppClientSize -Handle $h -Width 1920 -Height 1080 | Out-Null
Start-Sleep -Milliseconds 600

$sizes = @(
  @(2560,1410), @(1920,1080), @(1680,1050), @(1440,900),
  @(1366,768), @(1024,768), @(800,600), @(2560,1080), @(1280,1024)
)

function Capture-All([string]$name) {
  foreach ($s in $sizes) {
    Set-AppClientSize -Handle $h -Width $s[0] -Height $s[1] | Out-Null
    Start-Sleep -Milliseconds 650
    $p = Join-Path $Out ("{0}__{1}x{2}.png" -f $name, $s[0], $s[1])
    Save-AppShot -Handle $h -Path $p | Out-Null
  }
  Set-AppClientSize -Handle $h -Width 1920 -Height 1080 | Out-Null
  Start-Sleep -Milliseconds 500
  Write-Output "$name done"
}

# Назад к списку колод.
Invoke-AppClick -Handle $h -X 43 -Y 43 -DelayMs 900
# Статистика (боковая панель).
Invoke-AppClick -Handle $h -X 112 -Y 478 -DelayMs 1200
Capture-All "statistics"
Save-AppShot -Handle $h -Path (Join-Path $Out "_probe_statistics_top.png") | Out-Null
