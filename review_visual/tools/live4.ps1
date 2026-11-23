# Сценарий 4: тренировка, тест, ввод, пары, верно/неверно — по одному кадру + пробы.
param([string]$Out = "review_visual\screenshots")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")

$h = (Get-Process cardflow | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowHandle
Set-AppForeground -Handle $h
Set-AppClientSize -Handle $h -Width 1920 -Height 1080 | Out-Null
Start-Sleep -Milliseconds 500

function Shot([string]$name) {
  Park-AppMouse -Handle $h
  Save-AppShot -Handle $h -Path (Join-Path $Out ("{0}__1920x1080.png" -f $name)) | Out-Null
}
function Probe([string]$name) {
  Park-AppMouse -Handle $h
  Save-AppShot -Handle $h -Path (Join-Path $Out ("_probe_{0}.png" -f $name)) | Out-Null
}
function OpenSheet {
  Invoke-AppClick -Handle $h -X 960 -Y 415 -DelayMs 700
  Invoke-AppClick -Handle $h -X 960 -Y 415 -DelayMs 1200
}

# --- Тренировка ---
OpenSheet
Invoke-AppClick -Handle $h -X 960 -Y 551 -DelayMs 1700
Shot "practice_front"
Send-AppKey -Handle $h -Key "SPACE" -DelayMs 1100
Shot "practice_revealed"
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1100
Probe "practice_exit"
Invoke-AppClick -Handle $h -X 1077 -Y 605 -DelayMs 1300
Probe "practice_after"

# --- Тест ---
OpenSheet
Invoke-AppClick -Handle $h -X 960 -Y 672 -DelayMs 1700
Shot "study_test"
Probe "test_state"
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1100
Probe "test_after_esc"

# --- Ввод ответа ---
OpenSheet
Invoke-AppClick -Handle $h -X 960 -Y 795 -DelayMs 1700
Shot "study_typing"
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1100
Probe "typing_after"

# --- Подбор пар ---
OpenSheet
Invoke-AppClick -Handle $h -X 960 -Y 916 -DelayMs 1700
Shot "study_match"
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1100
Probe "match_after"

# --- Верно/неверно (пункт у нижней кромки листа) ---
OpenSheet
Invoke-AppClick -Handle $h -X 960 -Y 1012 -DelayMs 1700
Shot "study_truefalse"
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1100
Probe "tf_after"
Write-Output "batch4 done"
