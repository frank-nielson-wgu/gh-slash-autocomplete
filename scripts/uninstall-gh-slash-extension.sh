#!/usr/bin/env bash
# Removes the GitHub bot slash-command autocomplete extension from Google Chrome (macOS and Linux) and Chromium (Linux).
# Usage: uninstall-gh-slash-extension.sh [--no-pause]
#   --no-pause   never prompt (for CI and automation); browsers are left alone if running, and sudo is not asked for a password
#
# Run it as your normal user, not with sudo. On Linux the script asks for sudo itself to remove the toolbar-pin policy.

NO_PAUSE=false
for Arg in "$@"; do
    case "$Arg" in
        --no-pause) NO_PAUSE=true ;;
        -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $Arg" >&2; exit 2 ;;
    esac
done

# The shared lib-gh-slash-extension.sh is in scripts/ in the release zip, and next to this script in the repo.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR"; [ -f "$LIB_DIR/lib-gh-slash-extension.sh" ] || LIB_DIR="$SCRIPT_DIR/scripts"  # in the repo it is next to this script, in the release zip in scripts/
# shellcheck source=lib-gh-slash-extension.sh
source "$LIB_DIR/lib-gh-slash-extension.sh" || { echo "ERROR: lib-gh-slash-extension.sh not found. Keep the scripts folder next to this script." >&2; exit 1; }

check_platform uninstall-gh-slash-extension.bat
show_banner

DELETE_CRX=false  # Set to true if you also want the script to delete local .crx files

# The browsers with something to remove are the targets.
TARGETS=()
for Variant in $(all_variants); do
    if [ -f "$(ext_json "$Variant")" ] || { [ "$OS" = linux ] && [ -f "$(policy_file "$Variant")" ]; }; then TARGETS+=("$Variant"); fi
done
if [ "${#TARGETS[@]}" -eq 0 ]; then say "No installed copy of the extension was found." "$C_YELLOW"; fi

check_can_write "${TARGETS[@]}"  # before closing anything

# 1. The browser only notices the removal when it restarts. Offer to restart it. Unlike the installer, the removal
#    doesn't need it closed, so declining just means the user restarts it themselves.
close_running_browsers     "is running. It needs to be restarted for the removal to take effect."     "Close it now? It will be reopened with your tabs when the uninstall finishes (y/n)"     "Try again (y/n)? Choose n to restart it yourself later"     "${TARGETS[@]}" || say "Leaving the browser open; restart it yourself after the uninstall finishes." "$C_YELLOW"

# 2. Remove the External Extensions entries
for Variant in "${TARGETS[@]}"; do
    if [ -f "$(ext_json "$Variant")" ]; then
        rm -f "$(ext_json "$Variant")" && say "Removed $(ext_json "$Variant")" "$C_YELLOW"
    fi
done

# 3. Remove the toolbar-pin policies added during setup (Linux only, needs root)
if [ "$OS" = linux ]; then
    SUDO=()
    for Variant in "${TARGETS[@]}"; do
        [ -f "$(policy_file "$Variant")" ] || continue
        if [ "${#SUDO[@]}" -eq 0 ]; then
            if $NO_PAUSE; then SUDO=(sudo -n); else SUDO=(sudo); say "Removing the toolbar-pin policy needs administrator rights (sudo)." "$C_YELLOW"; fi
        fi
        if "${SUDO[@]}" rm -f "$(policy_file "$Variant")"; then
            say "Removed $(policy_file "$Variant")" "$C_YELLOW"
        else
            say "WARNING: Couldn't remove $(policy_file "$Variant"). Delete it yourself with: sudo rm '$(policy_file "$Variant")'" "$C_YELLOW"
        fi
    done
fi

# 4. Optionally delete local .crx files next to the script or in its parent folder
if $DELETE_CRX; then
    for Dir in "$SCRIPT_DIR" "$(dirname "$SCRIPT_DIR")"; do
        for File in "$Dir/$CRX_PREFIX"*.crx; do
            [ -f "$File" ] || continue
            rm -f "$File" && say "Deleted file: $File" "$C_YELLOW"
        done
    done
fi

say "
Rollback complete!" "$C_GREEN"

reopen_closed
if $REOPENED; then
    say "Next steps: In the browser, go to chrome://extensions -> click 'Remove' on the extension card if it still appears." "$C_CYAN"
else
    say "Next steps: Restart the browser (close all of its windows, then reopen it) -> go to chrome://extensions -> click 'Remove' on the extension card if it still appears." "$C_CYAN"
fi
wait_for_enter "
Press Enter to close this window"
