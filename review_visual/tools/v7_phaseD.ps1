# v7 phase D: study modes + feed + practice at 2560x1410.
# Leaves every mode through the standard exit dialog (red "Выйти" located by pixel scan).
param([string]$Out = "review_visual\screenshots\v7")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")
$root = (Get-Location).Path
$py = "python"

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
function DialogOpen {
  $tmp = Join-Path $Out "_tmp_dlg.png"
  Park-AppMouse -Handle $h
  Save-AppShot -Handle $h -Path $tmp | Out-Null
  $bmp = [System.Drawing.Bitmap]::FromFile((Join-Path $root $tmp))
  $p = $bmp.GetPixel(400, 40)
  $lum = 0.299 * $p.R + 0.587 * $p.G + 0.114 * $p.B
  $bmp.Dispose()
  return ($lum -lt 200)
}
function LeaveMode {
  Send-AppKey -Handle $h -Key "ESC" -DelayMs 1100
  if (-not (DialogOpen)) { Write-Output "no dialog after ESC"; return }
  $tmp = Join-Path $Out "_tmp_dlg.png"
  $res = & $py (Join-Path $PSScriptRoot "find_red.py") (Join-Path $root $tmp)
  Write-Output "RED $res"
  if ($res -eq "none") { Send-AppKey -Handle $h -Key "ESC" -DelayMs 800; return }
  $parts = $res.Split(" ")
  Invoke-AppClick -Handle $h -X ([int]$parts[0]) -Y ([int]$parts[1]) -DelayMs 1500
}
function OpenMode([int]$x, [int]$y) {
  Invoke-AppClick -Handle $h -X 1280 -Y 363 -DelayMs 1100
  Invoke-AppClick -Handle $h -X $x -Y $y -DelayMs 2600
}

# Тест
OpenMode 1007 1033
Shot "study_test"
LeaveMode
Shot "_after_test"

# Ввод ответа
OpenMode 1548 1033
Shot "study_typing"
LeaveMode
Shot "_after_typing"

# Подбор пар
OpenMode 1007 1157
Shot "study_match"
LeaveMode
Shot "_after_match"

# Верно/Неверно
OpenMode 1548 1157
Shot "study_truefalse"
LeaveMode
Shot "_after_tf"

# Лента
OpenMode 1548 739
Shot "feed_question"
Send-AppKey -Handle $h -Key "SPACE" -DelayMs 1200
Shot "feed_answer"
LeaveMode
Shot "_after_feed"

# Тренировка
OpenMode 1007 863
Shot "practice_question"
Send-AppKey -Handle $h -Key "SPACE" -DelayMs 1200
Shot "practice_answer"
LeaveMode
Shot "_after_practice"
