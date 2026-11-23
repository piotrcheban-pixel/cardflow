# v7 phase G: full resolution matrix with forced repaint before capture.
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
function Shot([string]$name) {
  Park-AppMouse -Handle $h
  $p = Join-Path $Out $name
  Save-AppShot -Handle $h -Path $p | Out-Null
  Write-Output "SHOT $p"
}
function CapSet([string]$name) {
  foreach ($s in $sizes) {
    Set-AppClientSize -Handle $h -Width $s[0] -Height $s[1] | Out-Null
    Start-Sleep -Milliseconds 400
    # Force a full repaint: hover inside the window, then park the pointer away.
    Move-AppMouse -Handle $h -X ([int]($s[0] / 2)) -Y ([int]($s[1] / 2)) -DelayMs 350
    Park-AppMouse -Handle $h
    Start-Sleep -Milliseconds 1200
    Shot ("{0}__{1}x{2}.png" -f $name, $s[0], $s[1])
  }
}
function LeaveDialog {
  Send-AppKey -Handle $h -Key "ESC" -DelayMs 1000
  $tmp = Join-Path $Out "_tmp_dlg.png"
  Park-AppMouse -Handle $h
  Save-AppShot -Handle $h -Path $tmp | Out-Null
  $bmp = [System.Drawing.Bitmap]::FromFile((Join-Path $root $tmp))
  $p = $bmp.GetPixel(400, 40)
  $lum = 0.299 * $p.R + 0.587 * $p.G + 0.114 * $p.B
  $bmp.Dispose()
  if ($lum -ge 200) { Write-Output "no dialog"; return $false }
  $res = & $py (Join-Path $PSScriptRoot "find_red.py") (Join-Path $root $tmp) 800 600 1800 1100
  if ($res -eq "none") { Send-AppKey -Handle $h -Key "ESC" -DelayMs 800; return $false }
  $parts = $res.Split(" ")
  Invoke-AppClick -Handle $h -X ([int]$parts[0]) -Y ([int]$parts[1]) -DelayMs 1600
  return $true
}

Set-AppClientSize -Handle $h -Width 2560 -Height 1410 | Out-Null
Start-Sleep -Milliseconds 700

# A. Leave the session if the exit dialog is open, then go to the decks shell.
if (LeaveDialog) { Write-Output "left session" }
Invoke-AppClick -Handle $h -X 180 -Y 258 -DelayMs 1600
Shot "_probe_G_decks.png"

# B. Clear the deck search filter if present, then the decks matrix.
Invoke-AppClick -Handle $h -X 1915 -Y 344 -DelayMs 800
CapSet "res_decks"

# C. Statistics.
Invoke-AppClick -Handle $h -X 180 -Y 464 -DelayMs 1800
Shot "_probe_G_stats.png"
CapSet "res_statistics"

# D. Settings.
Invoke-AppClick -Handle $h -X 180 -Y 533 -DelayMs 1800
Shot "_probe_G_settings.png"
CapSet "res_settings"

# E. Deck screen (Эл тех via the search field) — capture at 2K first.
Set-AppClientSize -Handle $h -Width 2560 -Height 1410 | Out-Null
Start-Sleep -Milliseconds 600
Invoke-AppClick -Handle $h -X 180 -Y 258 -DelayMs 1400
Invoke-AppClick -Handle $h -X 1248 -Y 519 -DelayMs 300
Send-AppText -Handle $h -Text "Эл тех" -DelayMs 1100
Invoke-AppClick -Handle $h -X 1400 -Y 900 -DelayMs 1800
Shot "_probe_G_deck.png"
CapSet "res_deck"

# F. Classic session.
Set-AppClientSize -Handle $h -Width 2560 -Height 1410 | Out-Null
Start-Sleep -Milliseconds 600
Invoke-AppClick -Handle $h -X 1280 -Y 363 -DelayMs 1200
Shot "_probe_G_sheet.png"
Invoke-AppClick -Handle $h -X 1007 -Y 739 -DelayMs 2800
Shot "_probe_G_session.png"
CapSet "res_classic_question"
Send-AppKey -Handle $h -Key "SPACE" -DelayMs 1500
CapSet "res_classic_answer"
