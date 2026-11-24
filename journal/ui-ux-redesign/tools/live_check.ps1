# Живая проверка редизайна v3: запуск Release-сборки, окно 1920x1080,
# снимки «Колоды» и листа режимов. Только чтение/навигация; процесс
# завершается принудительно, чтобы ничего не подтверждать. Запись —
# journal/ui-ux-redesign. Живой кадр самой ленты не снимается: окно на
# рабочем столе сжимается по высоте, автоматическая навигация по
# координатам ненадёжна (лента проверена production-рендерами и тестами).
$ErrorActionPreference = "Stop"
. (Join-Path (Get-Location) "review_final\tools\ui.ps1")
Add-Type -AssemblyName System.Windows.Forms

$Out = "journal\ui-ux-redesign\screenshots\live"
New-Item -ItemType Directory -Force $Out | Out-Null
New-Item -ItemType Directory -Force "journal\ui-ux-redesign\raw" | Out-Null

Get-Process cardflow -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 700
$exe = Join-Path (Get-Location) "build\windows\x64\runner\Release\cardflow.exe"
$proc = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) `
  -RedirectStandardOutput journal\ui-ux-redesign\raw\live_stdout.txt `
  -RedirectStandardError journal\ui-ux-redesign\raw\live_stderr.txt -PassThru
Write-Output ("STARTED pid={0}" -f $proc.Id)

$h = [IntPtr]::Zero
for ($i = 0; $i -lt 80; $i++) {
  Start-Sleep -Milliseconds 500
  $p = Get-Process cardflow -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($p) { $h = $p.MainWindowHandle; break }
}
if ($h -eq [IntPtr]::Zero) { throw "Окно cardflow не найдено" }
Set-AppForeground -Handle $h
Start-Sleep -Milliseconds 2600

function Resize([int]$w, [int]$hh, [int]$delay = 700) {
  Set-AppClientSize -Handle $h -Width $w -Height $hh | Out-Null
  Start-Sleep -Milliseconds $delay
}
function Shot([string]$name) {
  Park-AppMouse -Handle $h
  Save-AppShot -Handle $h -Path (Join-Path $Out ("{0}.png" -f $name)) | Out-Null
  Write-Output ("SHOT {0}" -f $name)
}
function Click([int]$x, [int]$y, [int]$delay = 900) {
  Invoke-AppClick -Handle $h -X $x -Y $y -DelayMs $delay
}

Resize 1920 1080 1200
Shot "live_01_decks_1920x1080"

# Первая колода в сетке (та же точка, что в предыдущих харнессах аудита).
Click 650 700 1600
Shot "live_02_decks_compact_1920x630"

# «Начать сессию» → лист режимов.
Click 600 330 1300
Shot "live_03_modes_sheet_1920x630"


Write-Output "LIVE CHECKS DONE"
Stop-Process -Id $proc.Id -Force
