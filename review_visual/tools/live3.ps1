# Сценарий 3: режимы обучения (тренировка/тест/ввод/пары/верно-неверно),
# статистика с прокруткой, вкладки настроек. Только навигация и скриншоты.
param([string]$Out = "review_visual\screenshots")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")

$h = (Get-Process cardflow | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowHandle
Set-AppForeground -Handle $h
Set-AppClientSize -Handle $h -Width 1920 -Height 1080 | Out-Null
Start-Sleep -Milliseconds 600

function Shot([string]$name) {
  Park-AppMouse -Handle $h
  Save-AppShot -Handle $h -Path (Join-Path $Out ($name + "__1920x1080.png")) | Out-Null
  Start-Sleep -Milliseconds 200
}

function ShotSizes([string]$name) {
  foreach ($s in @(@(2560,1410),@(800,600))) {
    Set-AppClientSize -Handle $h -Width $s[0] -Height $s[1] | Out-Null
    Start-Sleep -Milliseconds 700
    Park-AppMouse -Handle $h
    Save-AppShot -Handle $h -Path (Join-Path $Out ("{0}__{1}x{2}.png" -f $name, $s[0], $s[1])) | Out-Null
  }
  Set-AppClientSize -Handle $h -Width 1920 -Height 1080 | Out-Null
  Start-Sleep -Milliseconds 600
}

function OpenSheet {
  Invoke-AppClick -Handle $h -X 960 -Y 415 -DelayMs 700
  Invoke-AppClick -Handle $h -X 960 -Y 415 -DelayMs 1200
}

function ExitMode {
  Send-AppKey -Handle $h -Key "ESC" -DelayMs 1000
  Save-AppShot -Handle $h -Path (Join-Path $Out "_probe_exit_mode.png") | Out-Null
  Invoke-AppClick -Handle $h -X 1077 -Y 605 -DelayMs 1200
}

# Выход из ленты в колоду.
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1000
Invoke-AppClick -Handle $h -X 1077 -Y 605 -DelayMs 1300

# --- Тренировка ---
OpenSheet
Invoke-AppClick -Handle $h -X 960 -Y 551 -DelayMs 1600
Shot "practice_front"
Send-AppKey -Handle $h -Key "SPACE" -DelayMs 1200
Shot "practice_revealed"
ShotSizes "practice_revealed"
ExitMode

# --- Тест ---
OpenSheet
Invoke-AppClick -Handle $h -X 960 -Y 672 -DelayMs 1600
Shot "study_test"
ShotSizes "study_test"
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1000

# --- Ввод ответа ---
OpenSheet
Invoke-AppClick -Handle $h -X 960 -Y 795 -DelayMs 1600
Shot "study_typing"
ShotSizes "study_typing"
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1000

# --- Подбор пар ---
OpenSheet
Invoke-AppClick -Handle $h -X 960 -Y 916 -DelayMs 1600
Shot "study_match"
ShotSizes "study_match"
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1000

Save-AppShot -Handle $h -Path (Join-Path $Out "_probe_after_match.png") | Out-Null
Write-Output "batch3 done"
