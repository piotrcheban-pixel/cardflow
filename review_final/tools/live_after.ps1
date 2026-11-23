# Живые кадры «после» для финальной визуальной доводки CardFlow.
# Только навигация/ввод/скриншоты; файлы проекта не изменяются.
# Запись — review_final/screenshots/after и review_final/raw_after.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")
Add-Type -AssemblyName System.Windows.Forms

$Out = "review_final\screenshots\after"
New-Item -ItemType Directory -Force $Out | Out-Null
New-Item -ItemType Directory -Force "review_final\raw_after" | Out-Null

Get-Process cardflow -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 700
$exe = Join-Path (Get-Location) "build\windows\x64\runner\Debug\cardflow.exe"
$proc = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) `
  -RedirectStandardOutput review_final\raw_after\live_stdout.txt `
  -RedirectStandardError review_final\raw_after\live_stderr.txt -PassThru
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

function Key([string]$keys, [int]$delay = 700) {
  Set-AppForeground -Handle $h
  [System.Windows.Forms.SendKeys]::SendWait($keys)
  Start-Sleep -Milliseconds $delay
}

# --- 1. Колоды: 2K live и свип разрешений --------------------------------
Resize 1920 1080
Resize 2560 1410 900
Shot "live_00_decks_2560x1440"
Resize 1920 1080
foreach ($s in @("1920x1080","1680x1050","1440x900","1366x768","1280x1024","1024x768","800x600","2560x1080")) {
  $p = $s.Split("x")
  Resize ([int]$p[0]) ([int]$p[1]) 700
  $g = Get-AppGeometry -Handle $h
  Shot ("live_decks__{0}x{1}" -f $g.ClientW, $g.ClientH)
}
Resize 1920 1080

# --- 2. Колода «Электротехника» и лист режимов ---------------------------
Click 650 700 1500
Resize 2560 1410 900
Shot "live_01_deck_2560x1410"
Resize 1920 1080
Click 600 330 1200                   # «Начать сессию»
Resize 2560 1410 900
Shot "live_02_modes_sheet_2560x1410"
Resize 1920 1080
Click 700 410 1600                   # «Классический»
Resize 2560 1410 900
Shot "live_03_classic_Q_2560x1410"
Click 1280 700 1000                  # раскрыть ответ в 2K
Shot "live_04_classic_A_2560x1410"
Key "{ESC}" 900
Shot "live_05_exit_dialog_2560x1410"
Key "{ESC}" 600                      # закрыть диалог, остаться в сессии
Resize 1920 1080
Click 30 40 900                      # «×» сессии
Click 1253 610 1200                  # «Выйти» в диалоге
Click 40 40 900                      # назад к колодам
Write-Output "classic done"

# --- 3. Настройки, статистика, генерация ---------------------------------
Click 125 533 1400                   # «Настройки»
Resize 2560 1410 900
Shot "live_06_settings_2560x1410"
Resize 1920 1080
Click 125 459 1400                   # «Статистика»
Resize 2560 1410 900
Shot "live_07_statistics_2560x1410"
Resize 1920 1080
Click 125 256 1200                   # «Колоды»
Click 125 314 1600                   # «ИИ-генерация»
Resize 2560 1410 900
Shot "live_08_generation_2560x1410"
foreach ($s in @("1920x1080","1024x768","800x600","2560x1080")) {
  $p = $s.Split("x")
  Resize ([int]$p[0]) ([int]$p[1]) 650
  $g = Get-AppGeometry -Handle $h
  Shot ("live_generation__{0}x{1}" -f $g.ClientW, $g.ClientH)
}
Resize 1920 1080
Click 40 40 900                      # назад к колодам
Write-Output "settings/stats/gen done"

# --- 4. «Лента»: вопрос/ответ, выход -------------------------------------
Click 650 700 1400                   # колода
Click 600 330 1200                   # «Начать сессию»
Click 1200 410 1600                  # «Лента»
Resize 2560 1410 900
Shot "live_09_feed_Q_2560x1410"
Click 1280 700 1000                  # раскрыть
Shot "live_10_feed_A_2560x1410"
Key "{ESC}" 900
Shot "live_11_feed_exit_dialog_2560x1410"
Key "{ESC}" 500
Resize 1920 1080
Click 30 40 900
Click 1253 610 1100                  # выйти (если диалог)
Click 40 40 900                      # назад к колодам
Write-Output "feed done"

# --- 5. Тёмная тема недоступна без записи настроек: пропускаем -----------
Resize 1920 1080
Shot "_final_probe_1920"
Get-Process cardflow -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Output "DONE"

