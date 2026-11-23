# v7 phase F2: classic session resolution matrix (question + answer), live window.
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
Set-AppClientSize -Handle $h -Width 2560 -Height 1410 | Out-Null
Start-Sleep -Milliseconds 800
# Back to the deck from the card form.
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1400
Park-AppMouse -Handle $h
Save-AppShot -Handle $h -Path (Join-Path $Out "_probe_deck_before_session.png") | Out-Null
# Modes sheet -> classic.
Invoke-AppClick -Handle $h -X 1280 -Y 363 -DelayMs 1200
Park-AppMouse -Handle $h
Save-AppShot -Handle $h -Path (Join-Path $Out "_probe_sheet_before_session.png") | Out-Null
Invoke-AppClick -Handle $h -X 1007 -Y 739 -DelayMs 2800
CapSet "res_classic_question"
Send-AppKey -Handle $h -Key "SPACE" -DelayMs 1500
CapSet "res_classic_answer"
# Leave: restore 2K first, then Esc/red-exit.
Set-AppClientSize -Handle $h -Width 2560 -Height 1410 | Out-Null
Start-Sleep -Milliseconds 800
Send-AppKey -Handle $h -Key "ESC" -DelayMs 1200
$tmp = Join-Path $Out "_tmp_dlg.png"
Park-AppMouse -Handle $h
Save-AppShot -Handle $h -Path $tmp | Out-Null
$res = & $py (Join-Path $PSScriptRoot "find_red.py") (Join-Path $root $tmp) 1000 600 1600 1100
Write-Output "RED $res"
if ($res -ne "none") {
  $parts = $res.Split(" ")
  Invoke-AppClick -Handle $h -X ([int]$parts[0]) -Y ([int]$parts[1]) -DelayMs 1500
}
Park-AppMouse -Handle $h
Save-AppShot -Handle $h -Path (Join-Path $Out "_probe_after_matrix.png") | Out-Null
