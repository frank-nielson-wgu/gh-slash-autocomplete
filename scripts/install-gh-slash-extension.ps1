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
$ExtensionID = "aimpmkmhbohibcafaapmdhpmmofnpp"
$CrxPattern  = "gh-slash-autocomplete-*.crx"

# Resolve the repo root (the parent of the scripts folder, where the .crx lives)
$ScriptDir = Split-Path -Parent $(if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot })

# 1. Automatically find the most recently modified .crx in the repo root
$LatestCrx = Get-ChildItem -Path $ScriptDir -Filter $CrxPattern | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($null -eq $LatestCrx) {
    Write-Error "CRITICAL: No .crx file matching '$CrxPattern' found in $ScriptDir! Keep the .crx in the repo root (the parent of the scripts folder)."
    Wait-ForEnter "Press Enter to exit"
    exit 1
}

$CrxPath = $LatestCrx.FullName

# 2. Extract the exact version from manifest.json inside the .crx binary
Add-Type -AssemblyName System.IO.Compression.FileSystem
$CrxBytes = [System.IO.File]::ReadAllBytes($CrxPath)

# Locate the embedded ZIP archive header (PK\x03\x04) past the CRX3 header
$ZipOffset = -1
for ($i = 0; $i -lt [Math]::Min($CrxBytes.Length - 4, 8192); $i++) {
    if ($CrxBytes[$i] -eq 0x50 -and $CrxBytes[$i+1] -eq 0x4B -and $CrxBytes[$i+2] -eq 0x03 -and $CrxBytes[$i+3] -eq 0x04) {
        $ZipOffset = $i
        break
    }
}

if ($ZipOffset -lt 0) {
    Write-Error "Could not locate embedded ZIP payload inside $CrxPath"
    Wait-ForEnter "Press Enter to exit"
    exit 1
}

$TempZip = Join-Path $env:TEMP ("crx_inspect_" + [guid]::NewGuid().ToString() + ".zip")
try {
    [System.IO.File]::WriteAllBytes($TempZip, $CrxBytes[$ZipOffset..($CrxBytes.Length - 1)])
    $Zip = [System.IO.Compression.ZipFile]::OpenRead($TempZip)
    $ManifestEntry = $Zip.Entries | Where-Object { $_.FullName -eq "manifest.json" }
    
    if ($null -eq $ManifestEntry) {
        Write-Error "manifest.json not found inside $CrxPath"
        Wait-ForEnter "Press Enter to exit"
        exit 1
    }

    $Reader = New-Object System.IO.StreamReader($ManifestEntry.Open())
    $ManifestJson = $Reader.ReadToEnd() | ConvertFrom-Json
    $Reader.Close()
    $Zip.Dispose()

    $Version = $ManifestJson.version
}
finally {
    if (Test-Path $TempZip) { Remove-Item $TempZip -Force }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    Write-Error "Could not read 'version' from manifest.json inside $CrxPath"
    Wait-ForEnter "Press Enter to exit"
    exit 1
}

Write-Host "Detected $($LatestCrx.Name) -> Version $Version" -ForegroundColor Cyan

# 3. Force-close Chrome completely
cmd /c "taskkill /F /IM chrome.exe /T >nul 2>&1"; $global:LASTEXITCODE = 0  # run via cmd so a missing chrome.exe is neither an error nor the exit code
Start-Sleep -Seconds 2

# 4. Dynamically scan ALL Chrome profiles for the current user ($env:LOCALAPPDATA)
$UserDataDir = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
if (Test-Path $UserDataDir) {
    $ProfileDirs = Get-ChildItem -Path $UserDataDir -Directory | Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" }

    foreach ($Profile in $ProfileDirs) {
        $PrefFiles = @(
            (Join-Path $Profile.FullName "Preferences"),
            (Join-Path $Profile.FullName "Secure Preferences")
        )

        foreach ($File in $PrefFiles) {
            if (Test-Path $File) {
                Copy-Item -Path $File -Destination "$File.bak" -Force
                $Json = Get-Content -Path $File -Raw | ConvertFrom-Json
                $Modified = $false

                if ($null -ne $Json.extensions -and $null -ne $Json.extensions.settings) {
                    if ($Json.extensions.settings.PSObject.Properties.Name -contains $ExtensionID) {
                        $Json.extensions.settings.PSObject.Properties.Remove($ExtensionID)
                        $Modified = $true
                    }
                }

                if ($null -ne $Json.extensions -and $null -ne $Json.extensions.external_uninstalls) {
                    if ($Json.extensions.external_uninstalls -contains $ExtensionID) {
                        $Json.extensions.external_uninstalls = @($Json.extensions.external_uninstalls | Where-Object { $_ -ne $ExtensionID })
                        $Modified = $true
                    }
                }

                if ($Modified) {
                    $Json | ConvertTo-Json -Depth 100 -Compress | Set-Content -Path $File -Encoding UTF8
                    Write-Host "Cleared blacklist entry in [$($Profile.Name)] -> $(Split-Path $File -Leaf)" -ForegroundColor Yellow
                }
            }
        }
    }
}

# 5. Register the .crx and ExtensionSettings policy machine-wide
$RegPaths = @(
    "HKLM:\SOFTWARE\Google\Chrome\Extensions\$ExtensionID",
    "HKLM:\SOFTWARE\WOW6432Node\Google\Chrome\Extensions\$ExtensionID"
)

foreach ($Path in $RegPaths) {
    New-Item -Path $Path -Force | Out-Null
    New-ItemProperty -Path $Path -Name "path" -Value $CrxPath -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $Path -Name "version" -Value $Version -PropertyType String -Force | Out-Null
}

$PolicyPath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
$SettingsJson = @"
{
  "$ExtensionID": {
    "installation_mode": "allowed",
    "toolbar_pin": "force_pinned"
  }
}
"@

$CompactJson = ($SettingsJson | ConvertFrom-Json | ConvertTo-Json -Compress)
New-Item -Path $PolicyPath -Force | Out-Null
New-ItemProperty -Path $PolicyPath -Name "ExtensionSettings" -Value $CompactJson -PropertyType String -Force | Out-Null

Write-Host "`nSuccessfully registered $ExtensionID v$Version!" -ForegroundColor Green
Write-Host "Next steps: Open Chrome -> go to chrome://extensions -> toggle the extension ON once." -ForegroundColor Cyan
Wait-ForEnter "`nPress Enter to close this window"
