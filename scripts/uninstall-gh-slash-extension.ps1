param([switch]$NoPause)  # skip the "Press Enter" prompts (for CI and automation)
function Wait-ForEnter([string]$Prompt) { if (-not $NoPause) { Read-Host $Prompt } }

# --- 0. SELF-ELEVATE TO ADMINISTRATOR IF NEEDED ---
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        Write-Error "Please save this script as a .ps1 file before running, or open PowerShell as Administrator."
        exit 1
    }
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"$(if ($NoPause) { ' -NoPause' })"
    exit
}

# --- CONFIGURATION ---
$ExtensionID = "aimpmkmhbohibcafaapmdhpmpmmofnpp"
$CrxPattern  = "gh-slash-autocomplete-*.crx"
$DeleteCrx   = $false  # Set to $true if you also want the script to delete local .crx files

# Resolve the repo root (the parent of the scripts folder, where the .crx lives)
$ScriptDir = Split-Path -Parent $(if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot })

# 1. Force-close Chrome completely
cmd /c "taskkill /F /IM chrome.exe /T >nul 2>&1"; $global:LASTEXITCODE = 0  # run via cmd so a missing chrome.exe is neither an error nor the exit code
Start-Sleep -Seconds 2

# 2. Remove External Extension Registry entries (64-bit & 32-bit)
$RegPaths = @(
    "HKLM:\SOFTWARE\Google\Chrome\Extensions\$ExtensionID",
    "HKLM:\SOFTWARE\WOW6432Node\Google\Chrome\Extensions\$ExtensionID"
)

foreach ($Path in $RegPaths) {
    if (Test-Path -Path $Path) {
        Remove-Item -Path $Path -Recurse -Force
        Write-Host "Removed registry key: $Path" -ForegroundColor Yellow
    }
}

# 3. Remove local policy entries added during setup
$PolicyBase = "HKLM:\SOFTWARE\Policies\Google\Chrome"

if (Test-Path -Path $PolicyBase) {
    Remove-ItemProperty -Path $PolicyBase -Name "ExtensionSettings" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$PolicyBase\ExtensionInstallSources" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$PolicyBase\ExtensionInstallAllowlist" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned up local Chrome policy keys." -ForegroundColor Yellow
}

# 4. Optionally delete local .crx files in the repo root
if ($DeleteCrx) {
    $CrxFiles = Get-ChildItem -Path $ScriptDir -Filter $CrxPattern -ErrorAction SilentlyContinue
    foreach ($File in $CrxFiles) {
        Remove-Item -Path $File.FullName -Force
        Write-Host "Deleted file: $($File.FullName)" -ForegroundColor Yellow
    }
}

Write-Host "`nRollback complete!" -ForegroundColor Green
Write-Host "Next steps: Open Chrome -> go to chrome://extensions -> click 'Remove' on the extension card if it still appears." -ForegroundColor Cyan
Wait-ForEnter "`nPress Enter to close this window"
