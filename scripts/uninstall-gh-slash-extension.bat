@echo off
rem In the repo this .bat sits next to its .ps1; in the release zip it sits next to the .crx and the .ps1 is in scripts\.
set "PS1=%~dp0scripts\uninstall-gh-slash-extension.ps1"
if not exist "%PS1%" set "PS1=%~dp0uninstall-gh-slash-extension.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
