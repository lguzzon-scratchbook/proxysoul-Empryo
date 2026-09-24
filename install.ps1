# Empryo branch installer — Windows x64.
#
#   irm https://raw.githubusercontent.com/lguzzon-scratchbook/proxysoul-Empryo/develop/install.ps1 | iex
#
# Downloads the matching bundle zip from the fork's GitHub release,
# verifies size, extracts soulforge.exe + deps/ into %LOCALAPPDATA%\SoulForge\bin,
# adds to User PATH.
#
# Env: $env:EMPRYO_VERSION = "v2.20.25-develop.1"

$ErrorActionPreference = "Stop"
$Version = $env:EMPRYO_VERSION
if (-not $Version) { $Version = "v2.20.25-develop.1" }
$repo = "lguzzon-scratchbook/proxysoul-Empryo"

$arch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
if ($arch -ne "AMD64") { Write-Error "need x64 (got $arch)"; exit 1 }

$asset = "soulforge-$($Version -replace '^v','')-windows-x64.zip"
$url = "https://github.com/$repo/releases/download/$Version/$asset"
$installDir = Join-Path $env:LOCALAPPDATA "SoulForge\bin"
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "empryo-$Version"
$zip = "$tmp.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }

Write-Host "  downloading $asset ($Version)..."
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 600
if ((Get-Item $zip).Length -lt 1048576) { Write-Error "download too small, aborting"; exit 1 }

Write-Host "  extracting..."
Expand-Archive -Path $zip -DestinationPath $tmp -Force
$exe = Join-Path $tmp "soulforge.exe"
$deps = Join-Path $tmp "deps"
if (-not (Test-Path $exe)) {
  $exe = (Get-ChildItem $tmp -Recurse -Filter soulforge.exe | Select-Object -First 1).FullName
  $deps = Join-Path (Split-Path $exe) "deps"
}
$running = Get-Process -Name "soulforge" -ErrorAction SilentlyContinue
if ($running) { Stop-Process -Id $running.Id -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500 }

Move-Item -Path $exe -Destination (Join-Path $installDir "soulforge.exe") -Force
$d = Join-Path $installDir "deps"
if (Test-Path $d) { Remove-Item $d -Recurse -Force }
if (Test-Path $deps) { Move-Item -Path $deps -Destination $d -Force }
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Unblock-File -Path (Join-Path $installDir "soulforge.exe") -ErrorAction SilentlyContinue

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*SoulForge*bin*") {
  $new = if ($userPath) { "$installDir;$userPath" } else { $installDir }
  [Environment]::SetEnvironmentVariable("Path", $new, "User")
  Write-Host "  added to PATH (open a NEW terminal)"
}
Write-Host "  installed: $(Join-Path $installDir 'soulforge.exe')"
Write-Host "  try: soulforge --version"
