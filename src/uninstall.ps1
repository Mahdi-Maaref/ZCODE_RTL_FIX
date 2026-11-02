# =============================================================
#  ZCode Persian Patch - Uninstall
#  Restores the original ZCode index.html and removes the
#  Vazirmatn fonts. Run: double-click uninstall.cmd
# =============================================================
$ErrorActionPreference = 'Stop'

$asar = Join-Path $env:LOCALAPPDATA 'Programs\ZCode\resources\app.asar'
$backup = Join-Path $env:LOCALAPPDATA 'zcode-fa-patch\original-index.html.bak'

# ---------- restore index.html ----------
if (-not (Test-Path $backup)) {
  Write-Host "No backup found - ZCode was probably never patched. Nothing to do."
  exit 0
}
if (-not (Test-Path $asar)) {
  Write-Host "ERROR: app.asar not found at: $asar"
  exit 1
}

$fs = [System.IO.File]::Open($asar, 'Open', 'ReadWrite', 'Read')
try {
  $head = New-Object byte[] 16
  [void]$fs.Read($head, 0, 16)
  $headerSize = [BitConverter]::ToUInt32($head, 12)
  $jbuf = New-Object byte[] $headerSize
  $read = 0
  while ($read -lt $headerSize) {
    $r = $fs.Read($jbuf, $read, $headerSize - $read)
    if ($r -le 0) { throw 'unexpected end of file while reading header' }
    $read += $r
  }
  $json = [System.Text.Encoding]::UTF8.GetString($jbuf)

  # several packages ship their own index.html inside the archive; the real
  # ZCode renderer page is the one containing <title>ZCode</title>
  $found = $null
  foreach ($m in [regex]::Matches($json, '"index\.html":\{"size":(\d+),"offset":"(\d+)"')) {
    $cSize = [long]$m.Groups[1].Value
    $cOff  = [long]$m.Groups[2].Value
    $cBuf = New-Object byte[] $cSize
    $fs.Position = 8 + $headerSize + $cOff
    $read = 0
    while ($read -lt $cSize) {
      $r = $fs.Read($cBuf, $read, $cSize - $read)
      if ($r -le 0) { break }
      $read += $r
    }
    $cTxt = [System.Text.Encoding]::UTF8.GetString($cBuf)
    if ($cTxt.Contains('<title>ZCode</title>')) { $found = @{ size = $cSize; off = $cOff }; break }
  }
  if ($found -eq $null) { throw 'ZCode renderer index.html not found (unsupported ZCode version?)' }

  $orig = [System.IO.File]::ReadAllBytes($backup)
  if ($orig.Length -ne $found.size) {
    Write-Host "Backup does not match the installed ZCode version (it was probably updated since)."
    Write-Host "Restore skipped - just re-run install.cmd to re-apply the patch, or reinstall ZCode."
    exit 0
  }
  $fs.Position = 8 + $headerSize + $found.off
  $fs.Write($orig, 0, $orig.Length)
  Write-Host "[1/2] Original ZCode index.html restored."
}
finally { $fs.Close() }

# ---------- remove fonts ----------
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$reg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$fonts = @{
  'Vazirmatn-Regular.ttf' = 'Vazirmatn Regular (TrueType)'
  'Vazirmatn-Medium.ttf'  = 'Vazirmatn Medium (TrueType)'
  'Vazirmatn-Bold.ttf'    = 'Vazirmatn Bold (TrueType)'
}
foreach ($f in $fonts.Keys) {
  $dest = Join-Path $fontDir $f
  try { if (Test-Path $dest) { Remove-Item $dest -Force } }
  catch { Write-Host "      (font file in use, will disappear after reboot): $f" }
  Remove-ItemProperty -Path $reg -Name $fonts[$f] -ErrorAction SilentlyContinue
}
Remove-Item (Split-Path $backup) -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "[2/2] Vazirmatn fonts removed."
Write-Host ""
Write-Host "DONE! Fully close ZCode and reopen it to see the original state."
