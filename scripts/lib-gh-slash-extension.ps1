# Shared by install-gh-slash-extension.ps1 and uninstall-gh-slash-extension.ps1 (Windows); dot-sourced, not run.
# The calling script declares [switch]$NoPause, which these functions read.

# --- What we install ---
$ExtensionID = "aimpmkmhbohibcafaapmdhpmpmmofnpp"
$CrxPattern  = "gh-slash-autocomplete-*.crx"

# The repo root (the parent of the scripts folder, where the .crx lives)
$ScriptDir = Split-Path -Parent $(if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot })

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

# Relaunches the calling script as Administrator if it isn't one already (pass it $PSCommandPath), then exits.
function Request-Elevation([string]$ScriptPath) {
    $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($IsAdmin) { return }
    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        Write-Error "Please save this script as a .ps1 file before running, or open PowerShell as Administrator."
        exit 1
    }
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"$(if ($NoPause) { ' -NoPause' })"
    exit
}

function Show-Banner {
    if ($NoPause) { return }
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

function Test-ChromeRunning { [bool](Get-Process -Name chrome -ErrorAction SilentlyContinue) }

# If Chrome is running, offers to close it the way the user would (asking each window to close, not killing the
# process). Sets $script:ChromeExe to Chrome's path (for Restart-Chrome). Returns 'NotRunning', 'Closed' or 'StillRunning'.
function Stop-ChromeInteractive([string]$Message, [string]$ClosePrompt, [string]$RetryPrompt) {
    if (-not (Test-ChromeRunning)) { return 'NotRunning' }
    Write-Host $Message -ForegroundColor Yellow
    $Answer = if ($NoPause) { $false } else { Read-YesNo $ClosePrompt }

    $script:ChromeExe = (Get-Process -Name chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1).Path

    while ($Answer) {
        # Same as clicking the X on each window; Chrome shuts down normally and saves its state.
        Get-Process -Name chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object { [void]$_.CloseMainWindow() }

        $Deadline = (Get-Date).AddSeconds(5)
        while ((Test-ChromeRunning) -and (Get-Date) -lt $Deadline) { Start-Sleep -Milliseconds 250 }

        if (-not (Test-ChromeRunning)) { break }
        Write-Host "Chrome didn't close. It may be waiting on a dialog or running in the background (check the system tray)." -ForegroundColor Yellow
        $Answer = Read-YesNo $RetryPrompt
    }

    if (Test-ChromeRunning) { return 'StillRunning' }
    Start-Sleep -Seconds 1  # let Chrome finish writing its files
    Write-Host "Chrome closed." -ForegroundColor Cyan
    return 'Closed'
}

# Reopens Chrome with the previous tabs. Returns $true if it is running afterwards.
function Restart-Chrome([string]$ChromeExe) {
    # The calling script runs as Administrator, and Chrome must not. Opening a shortcut through Explorer (which runs as the
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
            while (-not (Test-ChromeRunning) -and (Get-Date) -lt $Deadline) { Start-Sleep -Milliseconds 250 }
            if (Test-ChromeRunning) { break }
        }
    } finally {
        Remove-Item $Shortcut -Force -ErrorAction SilentlyContinue
    }

    if (Test-ChromeRunning) {
        Write-Host "Reopened Chrome." -ForegroundColor Cyan
        return $true
    }
    Write-Warning "Couldn't reopen Chrome automatically after 4 tries. Please start Chrome yourself."
    return $false
}
