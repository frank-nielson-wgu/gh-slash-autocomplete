# GitHub Bot Slash-Command Autocomplete — Local Installation Guide

> ## Installing from the release zip?
>
> If you downloaded `gh-slash-autocomplete-install-<version>.zip` from the GitHub releases page, this is all you need:
>
> 1. **Unzip it into a permanent folder** (such as `C:\code\gh-slash-autocomplete`). Chrome loads the `.crx` straight from this folder, so don't move or delete it afterwards.
> 2. Double-click **`install-gh-slash-extension.bat`** (next to the `.crx`) and click **Yes** at the Administrator prompt.
> 3. Open Chrome, go to `chrome://extensions`, and turn the extension **ON** (one time only).
>
> To update, unzip the newer release into the same folder (replacing the files when asked) and run the installer again. To remove it, run `uninstall-gh-slash-extension.bat`.
>
> The rest of this guide covers the same steps in more detail. Where it says "repo root", read "the folder you unzipped into", and drop the `scripts\` prefix from the `.bat` paths: in the zip they sit next to the `.crx` (the `.ps1` files they call stay in `scripts\`). The `pack-extension` script is only in the repository, not the zip.

---

This repo contains the packaged Chrome extension (`.crx`) along with PowerShell scripts to install, update, and uninstall it on Windows, including support for managed Chrome browsers.

## Folder Contents

* `gh-slash-autocomplete-*.crx` — The packaged Chrome extension binary (in the repo root).
* `scripts/install-gh-slash-extension.bat` — Registers the extension in Chrome and pins it to the toolbar.
* `scripts/uninstall-gh-slash-extension.bat` — Removes the extension's registry and policy entries.
* `scripts/pack-extension.bat` — Builds the `.crx` from `src/`.

The `.bat` files are thin wrappers around the `.ps1` scripts of the same name in `scripts/`.

---

## Installation & Updates

> **Important:** Keep this folder in a **permanent location** on your computer (such as `C:\code\` or a cloned Git repository) before installing. Chrome references the `.crx` file directly from this path. Moving or deleting the folder later will break the extension.

### 1. Run the Installation Script

1. Double-click **`scripts\install-gh-slash-extension.bat`**.
2. Click **Yes** when prompted for Administrator (UAC) permission.
   * *Note: The script detects the newest `.crx` version in the repo root and configures the Windows Registry. If Chrome is open, it asks whether to close it (a normal close, like clicking the X on each window; and reopens it with your tabs when the install finishes). Chrome must be closed for the install to continue.*
3. Press **Enter** to close the PowerShell window once it finishes.

### 2. Enable the Extension (One-Time Step)

Because this extension is installed locally rather than through the public Chrome Web Store, Chrome keeps it toggled off by default on first install:

1. **Open Google Chrome** (the installer already reopened it if it closed it for you). Chrome only picks up the new registry entry at startup, which is why the installer needs it closed.
2. Navigate to **`chrome://extensions`**.
3. Find **GitHub bot slash-command autocomplete** and flip its **enable toggle switch ON**.
4. The extension icon will automatically pin to your Chrome toolbar and stay enabled across future restarts.

### Updating to a Newer Version

1. Place the new `gh-slash-autocomplete-<version>.crx` file in the repo root (the folder above `scripts/`).
2. Re-run **`scripts\install-gh-slash-extension.bat`**. It will automatically detect the newest `.crx` file, read its version number, and update Chrome.

---

## Uninstalling / Rollback

1. Double-click **`scripts\uninstall-gh-slash-extension.bat`**.
2. Click **Yes** when prompted for Administrator permission.
3. Restart Chrome (close all of its windows, then reopen it). The script does not close Chrome for you.
4. Go to **`chrome://extensions`** and click **Remove** on the extension card if it is still listed.

---

## Troubleshooting

* **Extension doesn't appear after running the install script:**
  * Make sure **all** Chrome windows were closed before reopening Chrome.
  * If the script stops because Chrome is still running (you answered `n`, or Chrome didn't close in time), close Chrome completely (all windows, and any Chrome icon in the system tray) and run the install script again. Nothing is changed when it stops.
  * Ensure the `.crx` file is in the **repo root**, the folder that contains `scripts/`.
* **Script is blocked by Windows Execution Policy:**
  * Open PowerShell in the repo root and run:
    ```powershell
    powershell -ExecutionPolicy Bypass -File .\scripts\install-gh-slash-extension.ps1
    ```
