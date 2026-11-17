# Builds dist/gh-slash-autocomplete-install-<version>.zip: the packed .crx plus the install and uninstall scripts,
# with the .bat launchers next to the .crx and the .ps1 scripts in scripts/, plus the src/ folder. Run scripts/pack-extension.ps1 first.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Add-Type -AssemblyName System.IO.Compression.FileSystem

$version = (Get-Content (Join-Path $root 'src/manifest.json') -Raw | ConvertFrom-Json).version
$crx = "gh-slash-autocomplete-$version.crx"
if (-not (Test-Path (Join-Path $root $crx))) {
  throw "$crx not found in the repo root. Run scripts/pack-extension.ps1 first."
}

# Path inside the zip -> file on disk. The extension's source (src/) is included too, for loading it unpacked by hand.
$files = [ordered]@{
  $crx                                      = $crx
  'INSTALL.txt'                             = 'INSTALL.txt'
  'install-gh-slash-extension.bat'           = 'scripts/install-gh-slash-extension.bat'
  'scripts/install-gh-slash-extension.ps1'   = 'scripts/install-gh-slash-extension.ps1'
  'uninstall-gh-slash-extension.bat'         = 'scripts/uninstall-gh-slash-extension.bat'
  'scripts/uninstall-gh-slash-extension.ps1' = 'scripts/uninstall-gh-slash-extension.ps1'
  'scripts/lib-gh-slash-extension.ps1'       = 'scripts/lib-gh-slash-extension.ps1'
  'install-gh-slash-extension.sh'            = 'scripts/install-gh-slash-extension.sh'
  'uninstall-gh-slash-extension.sh'          = 'scripts/uninstall-gh-slash-extension.sh'
  'scripts/lib-gh-slash-extension.sh'        = 'scripts/lib-gh-slash-extension.sh'
}

$srcRoot = Join-Path $root 'src'
foreach ($file in Get-ChildItem $srcRoot -Recurse -File) {
  $relative = $file.FullName.Substring($srcRoot.Length + 1).Replace('\', '/')
  $files["src/$relative"] = "src/$relative"
}

$zip = Join-Path $root "dist/gh-slash-autocomplete-install-$version.zip"
New-Item -ItemType Directory -Force dist | Out-Null
Remove-Item $zip -ErrorAction SilentlyContinue

# Build the zip by hand so entry names use forward slashes (Compress-Archive in PowerShell 5.1 uses backslashes).
$archive = [IO.Compression.ZipFile]::Open($zip, 'Create')
try {
  foreach ($entry in $files.GetEnumerator()) {
    $created = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $root $entry.Value), $entry.Key)
    # Mark the shell scripts you run (not the shared lib in scripts/) executable (Unix mode 0755 in the high 16 bits) so they run after unzipping on macOS and Linux.
    if ($entry.Key.EndsWith('.sh') -and $entry.Key -notlike 'scripts/*') { $created.ExternalAttributes = 0x81ED0000 }
  }
} finally {
  $archive.Dispose()
}
Write-Host "Created dist/gh-slash-autocomplete-install-$version.zip"
