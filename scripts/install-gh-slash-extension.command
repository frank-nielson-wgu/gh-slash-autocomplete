#!/bin/bash
# Double-click this file in Finder to run the installer in a Terminal window (the macOS counterpart of the .bat files).
# In the release zip this file is at the top and install-gh-slash-extension.sh is in scripts/; in the repo they are side by side.
Dir="$(cd "$(dirname "$0")" && pwd)"
[ -f "$Dir/install-gh-slash-extension.sh" ] || Dir="$Dir/scripts"
bash "$Dir/install-gh-slash-extension.sh" "$@"
exit $?
