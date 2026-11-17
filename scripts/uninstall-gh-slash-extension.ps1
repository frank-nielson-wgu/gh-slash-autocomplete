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

if (-not $NoPause) {
    # The extension's icon (a dark tile with a slash) in ASCII, so the output starts lower in the window.
    Write-Host @'
   ########################
 ############################
##################   #########
#################    #########
################    ##########
###############    ###########
##############    ############
#############    #############
############    ##############
###########    ###############
##########    ################
#########    #################
#########   ##################
 ############################
   ########################
'@ -ForegroundColor DarkGray
    Write-Host "  GitHub bot slash-command autocomplete`n" -ForegroundColor White
}

# --- CONFIGURATION ---
$ExtensionID = "aimpmkmhbohibcafaapmdhpmpmmofnpp"
$CrxPattern  = "gh-slash-autocomplete-*.crx"
$DeleteCrx   = $false  # Set to $true if you also want the script to delete local .crx files

# Resolve the repo root (the parent of the scripts folder, where the .crx lives)
$ScriptDir = Split-Path -Parent $(if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot })

# 1. Chrome only notices the removal when it restarts. Offer to close it the way the user would (asking each window
#    to close, not killing the process) and reopen it at the end. Unlike the installer, the removal doesn't need
#    Chrome closed, so declining just means the user restarts Chrome themselves.
$ClosedChrome = $false
if (Get-Process -Name chrome -ErrorAction SilentlyContinue) {
    Write-Host "Google Chrome is running. It needs to be restarted for the removal to take effect." -ForegroundColor Yellow
    $Answer = if ($NoPause) { $false } else { Read-YesNo "Close Chrome now? It will be reopened with your tabs when the uninstall finishes (y/n)" }

    $ChromeExe = (Get-Process -Name chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1).Path

    while ($Answer) {
        # Same as clicking the X on each window; Chrome shuts down normally and saves its state.
        Get-Process -Name chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object { [void]$_.CloseMainWindow() }

        $Deadline = (Get-Date).AddSeconds(5)
        while ((Get-Process -Name chrome -ErrorAction SilentlyContinue) -and (Get-Date) -lt $Deadline) { Start-Sleep -Milliseconds 250 }

        if (-not (Get-Process -Name chrome -ErrorAction SilentlyContinue)) { break }
        Write-Host "Chrome didn't close. It may be waiting on a dialog or running in the background (check the system tray)." -ForegroundColor Yellow
        $Answer = Read-YesNo "Try again (y/n)? Choose n to restart Chrome yourself later"
    }

    if (Get-Process -Name chrome -ErrorAction SilentlyContinue) {
        Write-Host "Leaving Chrome open; restart it yourself after the uninstall finishes." -ForegroundColor Yellow
    } elseif ($ChromeExe) {
        Start-Sleep -Seconds 1  # let Chrome finish writing its files
        $ClosedChrome = $true   # we closed it, so we reopen it at the end
        Write-Host "Chrome closed." -ForegroundColor Cyan
    }
}

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

$Reopened = $false
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

    $Reopened = [bool](Get-Process -Name chrome -ErrorAction SilentlyContinue)
    if ($Reopened) {
        Write-Host "Reopened Chrome." -ForegroundColor Cyan
    } else {
        Write-Warning "Couldn't reopen Chrome automatically after 4 tries. Please start Chrome yourself."
    }
}

if ($Reopened) {
    Write-Host "Next steps: In Chrome, go to chrome://extensions -> click 'Remove' on the extension card if it still appears." -ForegroundColor Cyan
} else {
    Write-Host "Next steps: Restart Chrome (close all of its windows, then reopen it) -> go to chrome://extensions -> click 'Remove' on the extension card if it still appears." -ForegroundColor Cyan
}
Wait-ForEnter "`nPress Enter to close this window"
