param([switch]$NoPause)  # skip the "Press Enter" prompts (for CI and automation)
function Wait-ForEnter([string]$Prompt) { if (-not $NoPause) { Read-Host $Prompt } }
function Read-YesNo([string]$Prompt) {  # one key press, no Enter; asks until it is y or n; returns $true for y
    while ($true) {
        Write-Host "$Prompt " -NoNewline
        if ([Console]::IsInputRedirected) {
            $Key = ((Read-Host).Trim() + ' ')[0]  # no real console (redirected input): fall back to typing + Enter
        } else {
            $Key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').Character
            Write-Host $Key
        }
        if ($Key -eq 'y') { return $true }
        if ($Key -eq 'n') { return $false }
        Write-Host "Please press y or n." -ForegroundColor Yellow
    }
}

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

if (-not $NoPause) { 1..8 | ForEach-Object { Write-Host ('#' * 60) } ; Write-Host "" }  # a block of # first, so the output starts lower in the window

# --- CONFIGURATION ---
$ExtensionID = "aimpmkmhbohibcafaapmdhpmpmmofnpp"
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

# 3. Chrome must be closed: it rewrites its Preferences files when it exits, which would undo the cleanup in step 4.
#    Offer to close it the way the user would (asking each window to close, not killing the process), or stop.
if (Get-Process -Name chrome -ErrorAction SilentlyContinue) {
    Write-Host "Google Chrome is running and must be closed to finish the install." -ForegroundColor Yellow
    $Answer = if ($NoPause) { $false } else { Read-YesNo "Close Chrome now? It will be reopened with your tabs when the install finishes (y/n)" }

    $ChromeExe = (Get-Process -Name chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1).Path

    while ($Answer) {
        # Same as clicking the X on each window; Chrome shuts down normally and saves its state.
        Get-Process -Name chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object { [void]$_.CloseMainWindow() }

        $Deadline = (Get-Date).AddSeconds(5)
        while ((Get-Process -Name chrome -ErrorAction SilentlyContinue) -and (Get-Date) -lt $Deadline) { Start-Sleep -Milliseconds 250 }

        if (-not (Get-Process -Name chrome -ErrorAction SilentlyContinue)) { break }
        Write-Host "Chrome didn't close. It may be waiting on a dialog or running in the background (check the system tray)." -ForegroundColor Yellow
        $Answer = Read-YesNo "Try again (y/n)? Choose n to close Chrome yourself"
    }

    if (Get-Process -Name chrome -ErrorAction SilentlyContinue) {
        Write-Error "Close Chrome completely (all windows, and any icon in the system tray), then run this installer again. Nothing was changed."
        Wait-ForEnter "Press Enter to exit"
        exit 1
    }
    Start-Sleep -Seconds 1  # let Chrome finish writing its files
    $ClosedChrome = $true   # we closed it, so we reopen it at the end
    Write-Host "Chrome closed." -ForegroundColor Cyan
}

# 4. Dynamically scan ALL Chrome profiles for the current user ($env:LOCALAPPDATA)
$UserDataDir = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
$ProfileDirs = @()
if (Test-Path $UserDataDir) {
    $ProfileDirs = @(Get-ChildItem -Path $UserDataDir -Directory | Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" })
}

if ($ProfileDirs.Count -gt 0) {
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
if ($ClosedChrome -and $ChromeExe -and (Test-Path $ChromeExe)) {
    # This script runs as Administrator, and Chrome must not. Opening a shortcut through Explorer (which runs as the
    # normal user) starts Chrome without elevation and lets us pass --restore-last-session to bring back the tabs.
    $Shortcut = Join-Path $env:TEMP "reopen-chrome-$([guid]::NewGuid()).lnk"
    try {
        $Link = (New-Object -ComObject WScript.Shell).CreateShortcut($Shortcut)
        $Link.TargetPath = $ChromeExe
        $Link.Arguments = "--restore-last-session"
        $Link.Save()

        # Launch, give Chrome 3 seconds to show up, and if it doesn't, retry (4 attempts in all).
        for ($Attempt = 1; $Attempt -le 4; $Attempt++) {
            Start-Process -FilePath explorer.exe -ArgumentList "`"$Shortcut`""
            $Deadline = (Get-Date).AddSeconds(3)
            while (-not (Get-Process -Name chrome -ErrorAction SilentlyContinue) -and (Get-Date) -lt $Deadline) { Start-Sleep -Milliseconds 250 }
            if (Get-Process -Name chrome -ErrorAction SilentlyContinue) { break }
        }
    } finally {
        Remove-Item $Shortcut -Force -ErrorAction SilentlyContinue
    }

    if (Get-Process -Name chrome -ErrorAction SilentlyContinue) {
        Write-Host "Reopened Chrome." -ForegroundColor Cyan
        Write-Host "Next steps: In Chrome, go to chrome://extensions -> toggle the extension ON once." -ForegroundColor Cyan
    } else {
        Write-Warning "Couldn't reopen Chrome automatically after 4 tries. Please start Chrome yourself."
        Write-Host "Next steps: Open Chrome -> go to chrome://extensions -> toggle the extension ON once." -ForegroundColor Cyan
    }
} else {
    Write-Host "Next steps: Open Chrome -> go to chrome://extensions -> toggle the extension ON once." -ForegroundColor Cyan
}
Wait-ForEnter "`nPress Enter to close this window"
