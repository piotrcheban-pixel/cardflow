# Сценарий 1: Колоды (все размеры) → Колода → лист режимов → сессия.
# Только навигация и скриншоты; оценок не ставит, данные не меняет.
param([string]$Out = "review_visual\screenshots")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")

$h = (Get-Process cardflow | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowHandle
Set-AppForeground -Handle $h

# Целевые размеры КЛИЕНТА в физических px (экран 2560x1440, DPI 144 → 1,5).
$sizes = @(
  @(2560,1410), @(1920,1080), @(1680,1050), @(1440,900),
  @(1366,768), @(1024,768), @(800,600), @(2560,1080), @(1280,1024)
)

function Capture-All([string]$name) {
  foreach ($s in $sizes) {
    Set-AppClientSize -Handle $h -Width $s[0] -Height $s[1] | Out-Null
    Start-Sleep -Milliseconds 700
    $p = Join-Path $Out ("{0}__{1}x{2}.png" -f $name, $s[0], $s[1])
    Save-AppShot -Handle $h -Path $p | Out-Null
  }
  $g = Set-AppClientSize -Handle $h -Width 1920 -Height 1080
  Start-Sleep -Milliseconds 500
  Write-Output ("{0}: done, logical {1}x{2}" -f $name, $g.LogicalW, $g.LogicalH)
}

# 1. Экран «Мои колоды».
Capture-All "decks"

# 2. Открываем первую колоду (карточка «Электротехника»).
Invoke-AppClick -Handle $h -X 760 -Y 585 -DelayMs 1200
Start-Sleep -Milliseconds 400
Save-AppShot -Handle $h -Path (Join-Path $Out "_probe_deck.png") | Out-Null
Capture-All "deck"

# 3. Лист режимов.
Save-AppShot -Handle $h -Path (Join-Path $Out "_probe_before_sheet.png") | Out-Null
