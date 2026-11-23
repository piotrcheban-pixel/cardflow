# v7 phase H: clean resolution matrix from the freshly restarted app (decks shell).
param([string]$Out = "review_visual\screenshots\v7")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")
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
    Move-AppMouse -Handle $h -X ([int]($s[0] / 2)) -Y ([int]($s[1] / 2)) -DelayMs 350
    Park-AppMouse -Handle $h
    Start-Sleep -Milliseconds 1200
    Shot ("{0}__{1}x{2}.png" -f $name, $s[0], $s[1])
  }
}
function Restore2K {
  Set-AppClientSize -Handle $h -Width 2560 -Height 1410 | Out-Null
  Start-Sleep -Milliseconds 900
}

Restore2K
CapSet "res_decks"

Restore2K
Invoke-AppClick -Handle $h -X 180 -Y 464 -DelayMs 1800
Shot "_probe_H_stats.png"
CapSet "res_statistics"

Restore2K
Invoke-AppClick -Handle $h -X 180 -Y 533 -DelayMs 1800
Shot "_probe_H_settings.png"
CapSet "res_settings"

Restore2K
Invoke-AppClick -Handle $h -X 180 -Y 258 -DelayMs 1600
Invoke-AppClick -Handle $h -X 2000 -Y 1150 -DelayMs 1800
Shot "_probe_H_deck.png"
CapSet "res_deck"

Restore2K
Invoke-AppClick -Handle $h -X 1280 -Y 363 -DelayMs 1300
Shot "_probe_H_sheet.png"
Invoke-AppClick -Handle $h -X 1007 -Y 739 -DelayMs 2800
Shot "_probe_H_session.png"
CapSet "res_classic_question"
Send-AppKey -Handle $h -Key "SPACE" -DelayMs 1500
CapSet "res_classic_answer"
