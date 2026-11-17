param([switch]$NoPause)  # skip the "Press Enter" prompts (for CI and automation)
. (Join-Path $(if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot }) 'lib-gh-slash-extension.ps1')  # shared helpers; sits next to this script

# --- 0. SELF-ELEVATE TO ADMINISTRATOR IF NEEDED ---
Request-Elevation $PSCommandPath

Show-Banner

$DeleteCrx = $false  # Set to $true if you also want the script to delete local .crx files

# 1. Chrome only notices the removal when it restarts. Offer to close it the way the user would (asking each window
#    to close, not killing the process) and reopen it at the end. Unlike the installer, the removal doesn't need
#    Chrome closed, so declining just means the user restarts Chrome themselves.
$ChromeState = Stop-ChromeInteractive `
    -Message "Google Chrome is running. It needs to be restarted for the removal to take effect." `
    -ClosePrompt "Close Chrome now? It will be reopened with your tabs when the uninstall finishes (y/n)" `
    -RetryPrompt "Try again (y/n)? Choose n to restart Chrome yourself later"
if ($ChromeState -eq 'StillRunning') {
    Write-Host "Leaving Chrome open; restart it yourself after the uninstall finishes." -ForegroundColor Yellow
}
$ClosedChrome = $ChromeState -eq 'Closed'  # we closed it, so we reopen it at the end

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

$Reopened = $ClosedChrome -and $ChromeExe -and (Test-Path $ChromeExe) -and (Restart-Chrome $ChromeExe)

if ($Reopened) {
    Write-Host "Next steps: In Chrome, go to chrome://extensions -> click 'Remove' on the extension card if it still appears." -ForegroundColor Cyan
} else {
    Write-Host "Next steps: Restart Chrome (close all of its windows, then reopen it) -> go to chrome://extensions -> click 'Remove' on the extension card if it still appears." -ForegroundColor Cyan
}
Wait-ForEnter "`nPress Enter to close this window"
