# v7 phase E: feed answer + practice (retry after the fullscreen-viewer mishap).
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
function LeaveMode {
  Send-AppKey -Handle $h -Key "ESC" -DelayMs 1000
  $tmp = Join-Path $Out "_tmp_dlg.png"
  Park-AppMouse -Handle $h
  Save-AppShot -Handle $h -Path $tmp | Out-Null
  $bmp = [System.Drawing.Bitmap]::FromFile((Join-Path $root $tmp))
  $p = $bmp.GetPixel(400, 40)
  $lum = 0.299 * $p.R + 0.587 * $p.G + 0.114 * $p.B
  $bmp.Dispose()
  if ($lum -ge 200) { Write-Output "no dialog"; return }
  # Red "Выйти" inside the centred dialog only.
  $res = & $py (Join-Path $PSScriptRoot "find_red.py") (Join-Path $root $tmp) 1000 600 1600 1100
  Write-Output "RED $res"
  if ($res -eq "none") { Send-AppKey -Handle $h -Key "ESC" -DelayMs 800; return }
  $parts = $res.Split(" ")
  Invoke-AppClick -Handle $h -X ([int]$parts[0]) -Y ([int]$parts[1]) -DelayMs 1600
}

# Feed: reveal the current card and capture at once (auto-advance is 5 s).
Invoke-AppClick -Handle $h -X 1280 -Y 629 -DelayMs 350
Park-AppMouse -Handle $h
Save-AppShot -Handle $h -Path (Join-Path $Out "2k_feed_answer.png") | Out-Null
Write-Output "SHOT feed_answer"
LeaveMode
Shot "_after_feed2"

# Тренировка
Invoke-AppClick -Handle $h -X 1280 -Y 363 -DelayMs 1100
Invoke-AppClick -Handle $h -X 1007 -Y 863 -DelayMs 2600
Shot "practice_question"
Send-AppKey -Handle $h -Key "SPACE" -DelayMs 1300
Shot "practice_answer"
LeaveMode
Shot "_after_practice2"
