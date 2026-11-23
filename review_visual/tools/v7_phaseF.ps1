# v7 phase F: resolution matrix for four states (decks, deck, classic question/answer, settings).
# Live window is capped by the host display: client max ~2564x1410, so 3840x2160 is
# covered by widget tests instead (see v7_shots_test.dart).
param([string]$Out = "review_visual\screenshots\v7")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")
$root = (Get-Location).Path
$py = "python"

$h = (Get-Process cardflow | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowHandle
Set-AppForeground -Handle $h

$sizes = @(
  @(2560, 1410), @(1920, 1080), @(1680, 1050), @(1440, 900), @(1366, 768),
  @(1024, 768), @(800, 600), @(2560, 1080), @(1280, 1024)
)

function CapSet([string]$name) {
  foreach ($s in $sizes) {
    Set-AppClientSize -Handle $h -Width $s[0] -Height $s[1] | Out-Null
    Start-Sleep -Milliseconds 900
    $p = Join-Path $Out ("{0}__{1}x{2}.png" -f $name, $s[0], $s[1])
    Park-AppMouse -Handle $h
    Save-AppShot -Handle $h -Path $p | Out-Null
    Write-Output "SHOT $p"
  }
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
  $res = & $py (Join-Path $PSScriptRoot "find_red.py") (Join-Path $root $tmp) 900 ($([int]($bmp.Height / 3))) 1800 ($([int]($bmp.Height / 3 * 2)))
  if ($res -eq "none") { Send-AppKey -Handle $h -Key "ESC" -DelayMs 800; return }
  $parts = $res.Split(" ")
  Invoke-AppClick -Handle $h -X ([int]$parts[0]) -Y ([int]$parts[1]) -DelayMs 1500
}

Set-AppClientSize -Handle $h -Width 2560 -Height 1410 | Out-Null
Start-Sleep -Milliseconds 800

# 1. Shell: decks at every size.
CapSet "res_decks"

# 2. Statistics at every size (from the shell sidebar) — layout-heavy screen.
Invoke-AppClick -Handle $h -X 180 -Y 464 -DelayMs 1600
CapSet "res_statistics"

# 3. Settings at every size.
Invoke-AppClick -Handle $h -X 180 -Y 533 -DelayMs 1600
CapSet "res_settings"

# 4. Deck screen at every size.
Invoke-AppClick -Handle $h -X 180 -Y 258 -DelayMs 1400
Invoke-AppClick -Handle $h -X 775 -Y 900 -DelayMs 1600
CapSet "res_deck"

# 5. Classic question + answer at every size.
Invoke-AppClick -Handle $h -X 1280 -Y 363 -DelayMs 1100
Invoke-AppClick -Handle $h -X 1007 -Y 739 -DelayMs 2600
CapSet "res_classic_question"
Send-AppKey -Handle $h -Key "SPACE" -DelayMs 1400
CapSet "res_classic_answer"
LeaveMode
