# GitHub Bot Slash-Command Autocomplete — Local Installation Guide

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
   * *Note: The script will automatically close open Chrome windows, detect the newest `.crx` version in the repo root, and configure the Windows Registry.*
3. Press **Enter** to close the PowerShell window once it finishes.

### 2. Enable the Extension (One-Time Step)

Because this extension is installed locally rather than through the public Chrome Web Store, Chrome keeps it toggled off by default on first install:

1. Open **Google Chrome**.
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
3. Open Chrome, go to **`chrome://extensions`**, and click **Remove** on the extension card if it is still listed.

---

## Troubleshooting

* **Extension doesn't appear after running the install script:**
  * Make sure **all** Chrome windows were closed before reopening Chrome.
  * Ensure the `.crx` file is in the **repo root**, the folder that contains `scripts/`.
* **Script is blocked by Windows Execution Policy:**
  * Open PowerShell in the repo root and run:
    ```powershell
    powershell -ExecutionPolicy Bypass -File .\scripts\install-gh-slash-extension.ps1
    ```
