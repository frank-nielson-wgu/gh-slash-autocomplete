# Builds dist/gh-slash-autocomplete-<version>.zip for upload to the Chrome Web Store.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
Add-Type -AssemblyName System.IO.Compression.FileSystem

# The extension lives in src/; its files go into the zip at paths relative to that folder.
$src = Join-Path $PSScriptRoot "src"

$files = @(
  'manifest.json', 'background.js',
  'content/content.css', 'content/content.js', 'content/state.js', 'content/scan.js', 'content/menu.js',
  'options/options.html', 'options/options.css', 'options/options.js', 'options/validation.js', 'options/share.js',
  'shared/matching.js', 'shared/search.js'
) + (Get-ChildItem (Join-Path $src icons) -File | ForEach-Object { "icons/$($_.Name)" })

$version = (Get-Content (Join-Path $src manifest.json) -Raw | ConvertFrom-Json).version
$zip = Join-Path $PSScriptRoot "dist/gh-slash-autocomplete-$version.zip"

New-Item -ItemType Directory -Force dist | Out-Null
Remove-Item $zip -ErrorAction SilentlyContinue

# Compress-Archive in Windows PowerShell 5.1 writes backslash entry names, so build the zip by hand.
$archive = [IO.Compression.ZipFile]::Open($zip, 'Create')
try {
  foreach ($file in $files) {
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $src $file), $file)
  }
} finally {
  $archive.Dispose()
}
Write-Host "Created dist/gh-slash-autocomplete-$version.zip"

# Also copy it to the Downloads folder, which is under the home folder on Windows and macOS alike.
$downloads = Join-Path $HOME 'Downloads'
if (Test-Path $downloads -PathType Container) {
  Copy-Item $zip $downloads -Force
  Write-Host "Copied it to $downloads"
} else {
  Write-Warning "No Downloads folder at $downloads; skipped the copy."
}
