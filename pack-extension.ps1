# --- CONFIGURATION ---
$ScriptDir = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot }
$SourceDir = Join-Path $ScriptDir "src"             # Path to the folder containing manifest.json
$PemKey    = "C:\code\gh-slash-autocomplete.pem" # Path to your permanent .pem private key
$OutDir    = $ScriptDir                             # Where to save the final .crx

function Exit-WithPause {
    param([int]$Code = 0)
    Read-Host "`nPress Enter to close this window"
    exit $Code
}

Write-Host "=== Step 1: Locating Google Chrome ===" -ForegroundColor Cyan
$ChromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$ChromeExe = $ChromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($null -eq $ChromeExe) {
    Write-Host "[ERROR] Google Chrome executable not found!" -ForegroundColor Red
    Exit-WithPause 1
}
Write-Host "  Found Chrome at: $ChromeExe" -ForegroundColor Gray

Write-Host "`n=== Step 2: Validating Source Folder & Private Key ===" -ForegroundColor Cyan
Write-Host "  Checking source folder: $SourceDir" -ForegroundColor Gray
$ManifestPath = Join-Path $SourceDir "manifest.json"
if (-not (Test-Path $ManifestPath)) {
    Write-Host "[ERROR] manifest.json not found at: $ManifestPath" -ForegroundColor Red
    Write-Host "  Make sure '$SourceDir' points to the folder containing manifest.json." -ForegroundColor Yellow
    Exit-WithPause 1
}

Write-Host "  Checking private key:   $PemKey" -ForegroundColor Gray
if (-not (Test-Path $PemKey)) {
    Write-Host "[ERROR] Private key not found at: $PemKey" -ForegroundColor Red
    Write-Host "  Update `$PemKey to point to your existing .pem file so your Extension ID stays the same." -ForegroundColor Yellow
    Exit-WithPause 1
}
Write-Host "  Source and private key verified." -ForegroundColor Green

Write-Host "`n=== Step 3: Reading Version from manifest.json ===" -ForegroundColor Cyan
$Manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
$Version  = $Manifest.version
if ([string]::IsNullOrWhiteSpace($Version)) {
    Write-Host "[ERROR] Could not read 'version' from $ManifestPath" -ForegroundColor Red
    Exit-WithPause 1
}
Write-Host "  Detected extension version: v$Version" -ForegroundColor Green

Write-Host "`n=== Step 4: Preparing Output Paths ===" -ForegroundColor Cyan
$ParentDir    = Split-Path -Path $SourceDir -Parent
$FolderName   = Split-Path -Path $SourceDir -Leaf
$GeneratedCrx = Join-Path $ParentDir "$FolderName.crx"
$FinalCrxPath = Join-Path $OutDir "gh-slash-autocomplete-$Version.crx"

if (Test-Path $GeneratedCrx) {
    Write-Host "  Removing old temporary file: $GeneratedCrx" -ForegroundColor Gray
    Remove-Item $GeneratedCrx -Force
}
if (Test-Path $FinalCrxPath) {
    Write-Host "  Removing existing output file: $FinalCrxPath" -ForegroundColor Gray
    Remove-Item $FinalCrxPath -Force
}

Write-Host "`n=== Step 5: Packing Extension via Chrome CLI ===" -ForegroundColor Cyan
$TempProfile = Join-Path $env:TEMP ("chrome-pack-" + [guid]::NewGuid().ToString())
$ArgsList = @(
    "--user-data-dir=`"$TempProfile`"",
    "--pack-extension=`"$SourceDir`"",
    "--pack-extension-key=`"$PemKey`""
)

Write-Host "  Running Chrome packer..." -ForegroundColor Gray
$Process = Start-Process -FilePath $ChromeExe -ArgumentList $ArgsList -Wait -PassThru

# Clean up temporary profile folder
if (Test-Path $TempProfile) {
    Remove-Item -Path $TempProfile -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $GeneratedCrx)) {
    Write-Host "[ERROR] Chrome finished (Exit Code: $($Process.ExitCode)) but did not create $GeneratedCrx." -ForegroundColor Red
    Write-Host "  Check manifest.json for syntax errors or invalid file paths." -ForegroundColor Yellow
    Exit-WithPause 1
}
Write-Host "  Raw .crx generated successfully." -ForegroundColor Green

Write-Host "`n=== Step 6: Renaming & Finalizing Package ===" -ForegroundColor Cyan
Move-Item -Path $GeneratedCrx -Destination $FinalCrxPath -Force
Write-Host "  SUCCESS! Created: $FinalCrxPath" -ForegroundColor Green

Exit-WithPause 0
