# Снимок ТЕКУЩЕГО экрана CardFlow в наборе размеров клиентской области.
# Только чтение состояния приложения; запись — в review_final/screenshots.
#   . review_final/tools/ui.ps1
#   .\review_final\tools\sweep.ps1 -Name generation -Sizes 1920x1080,1024x768
param(
  [Parameter(Mandatory = $true)][string]$Name,
  [string[]]$Sizes = @('2560x1410', '1920x1080', '1680x1050', '1440x900',
    '1366x768', '1280x1024', '1024x768', '800x600', '2560x1080')
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ui.ps1")
$h = (Get-Process cardflow | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowHandle
Set-AppForeground -Handle $h
$out = "review_final\screenshots"
foreach ($s in $Sizes) {
  $parts = $s.Split('x')
  $w = [int]$parts[0]; $hh = [int]$parts[1]
  Set-AppClientSize -Handle $h -Width $w -Height $hh -X 0 -Y 0 | Out-Null
  Start-Sleep -Milliseconds 1000
  $g = Get-AppGeometry -Handle $h
  Park-AppMouse -Handle $h
  $path = Join-Path $out ("live_{0}__{1}x{2}.png" -f $Name, $g.ClientW, $g.ClientH)
  Save-AppShot -Handle $h -Path $path | Out-Null
  Write-Output ("{0} client={1}x{2} logical={3}x{4} dpi={5}" -f `
      $path, $g.ClientW, $g.ClientH, $g.LogicalW, $g.LogicalH, $g.Dpi)
}
