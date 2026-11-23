# v7 phase F3: size matrix from an already-open classic session (question state).
param([string]$Out = "review_visual\screenshots\v7")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")
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
CapSet "res_classic_question"
Send-AppKey -Handle $h -Key "SPACE" -DelayMs 1500
CapSet "res_classic_answer"
