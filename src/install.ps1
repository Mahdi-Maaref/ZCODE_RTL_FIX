# =============================================================
#  ZCode Persian Patch - RTL + Vazirmatn font
#  No prerequisites. Patches ZCode's app.asar in place.
#  Run: double-click install.cmd (or: powershell -File install.ps1)
# =============================================================
param([string]$AsarPath = "")
$ErrorActionPreference = 'Stop'

$defaultAsar = Join-Path $env:LOCALAPPDATA 'Programs\ZCode\resources\app.asar'
$asar = if ($AsarPath -ne "") { $AsarPath } else { $defaultAsar }
if (-not (Test-Path $asar)) {
  Write-Host "ERROR: app.asar not found at:"
  Write-Host "  $asar"
  Write-Host "Is ZCode installed? If it is installed somewhere else, pass the path:"
  Write-Host "  powershell -File install.ps1 -AsarPath `"C:\...\resources\app.asar`""
  exit 1
}
Write-Host "ZCode found: $asar"

$backupDir = Join-Path $env:LOCALAPPDATA 'zcode-fa-patch'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

# ---------- [1/3] Install Vazirmatn fonts (per-user, no admin needed) ----------
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
$reg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
if (-not (Test-Path $reg)) { New-Item -Path $reg -Force | Out-Null }
$fonts = @{
  'Vazirmatn-Regular.ttf' = 'Vazirmatn Regular (TrueType)'
  'Vazirmatn-Medium.ttf'  = 'Vazirmatn Medium (TrueType)'
  'Vazirmatn-Bold.ttf'    = 'Vazirmatn Bold (TrueType)'
}
foreach ($f in $fonts.Keys) {
  $dest = Join-Path $fontDir $f
  if (Test-Path $dest) {
    Write-Host "      font already installed: $f"
  }
  else {
    try {
      Copy-Item (Join-Path (Join-Path $PSScriptRoot 'fonts') $f) $dest -Force
    }
    catch {
      # font file can be locked by the Windows font cache on re-runs
      if (Test-Path $dest) { Write-Host "      font already installed: $f" }
      else { throw }
    }
  }
  New-ItemProperty -Path $reg -Name $fonts[$f] -Value $dest -PropertyType String -Force | Out-Null
}
Write-Host "[1/3] Vazirmatn fonts installed."

# ---------- [2/3] Patch app.asar ----------
$fs = [System.IO.File]::Open($asar, 'Open', 'ReadWrite', 'Read')
try {
  # parse the asar header to locate /out/renderer/index.html
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
    if ($cTxt.Contains('<title>ZCode</title>')) { $found = @{ size = $cSize; off = $cOff; buf = $cBuf; txt = $cTxt }; break }
  }
  if ($found -eq $null) { throw 'ZCode renderer index.html not found (unsupported ZCode version?)' }
  $size = $found.size
  $abs  = 8 + $headerSize + $found.off

  # read the original index.html
  $region = $found.buf
  $html = $found.txt

  if ($html.Contains('id="zcode-fa-patch"')) {
    Write-Host "[2/3] ZCode is already patched - skipping."
    Write-Host ""
    Write-Host "DONE. Fully close ZCode (all windows + tray) and reopen it."
    exit 0
  }

  # keep a backup so uninstall.ps1 can restore the original
  [System.IO.File]::WriteAllBytes((Join-Path $backupDir 'original-index.html.bak'), $region)

  $inj = @'
<style id="zcode-fa-patch">
  :root {
    --font-sans: 'Vazirmatn', ui-sans-serif, system-ui, 'Segoe UI', sans-serif;
  }
  html, body {
    font-family: 'Vazirmatn', ui-sans-serif, system-ui, 'Segoe UI', sans-serif !important;
  }
  p, h1, h2, h3, h4, h5, h6, li, blockquote, td, th, figcaption, dt, dd, textarea, input {
    unicode-bidi: plaintext;
  }
</style>
<script id="zcode-fa-rtl">
(function () {
  var SEL = 'p,h1,h2,h3,h4,h5,h6,li,blockquote,td,th,figcaption,dt,dd,textarea,input:not([type="checkbox"]):not([type="radio"]):not([type="hidden"])';
  var scheduled = false;
  function apply() {
    scheduled = false;
    var root = document.body;
    if (!root) return;
    var nodes = root.querySelectorAll(SEL);
    for (var i = 0; i < nodes.length; i++) {
      if (!nodes[i].hasAttribute('dir')) nodes[i].setAttribute('dir', 'auto');
    }
  }
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(apply);
  }
  function start() {
    apply();
    new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
</script>
'@

  # inject before </head>, removing bytes from the (performance-only)
  # modulepreload hint list and padding with an HTML comment so the file
  # size stays byte-identical - no asar rebuild needed
  $aIdx = $html.IndexOf('</head>')
  if ($aIdx -lt 0) { throw '</head> not found' }
  $mpS = $html.IndexOf('<link rel="modulepreload"')
  $mpE = $html.LastIndexOf('<link rel="stylesheet"')
  if ($mpS -lt 0 -or $mpE -le $mpS) { throw 'modulepreload region not found' }
  $regionLen = $mpE - $mpS
  $pad = $regionLen - $inj.Length - 7   # '<!--' (4) + '-->' (3)
  if ($pad -lt 0) { throw 'injection too large for available space' }
  $newRegion = $inj + '<!--' + (' ' * $pad) + '-->'
  $newHtml = $html.Substring(0, $mpS) + $newRegion + $html.Substring($mpE)
  $nb = [System.Text.Encoding]::UTF8.GetBytes($newHtml)
  if ($nb.Length -ne $size) { throw ("byte-length mismatch: {0} != {1}" -f $nb.Length, $size) }

  $fs.Position = $abs
  $fs.Write($nb, 0, $nb.Length)
  Write-Host "[2/3] app.asar patched (RTL + Vazirmatn)."
}
finally { $fs.Close() }

Write-Host "[3/3] Backup saved to: $backupDir"
Write-Host ""
Write-Host "DONE! Now fully close ZCode (all windows + tray icon) and reopen it."
