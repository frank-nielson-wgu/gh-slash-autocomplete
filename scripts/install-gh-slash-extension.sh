#!/usr/bin/env bash
# Installs (or updates) the GitHub bot slash-command autocomplete extension in Google Chrome (macOS and Linux)
# and in Chromium (Linux). Every one of those browsers found on this computer is set up.
# Usage: install-gh-slash-extension.sh [--no-pause]
#   --no-pause   never prompt (for CI and automation); browsers are left alone if running, and sudo is not asked for a password
#
# Run it as your normal user, not with sudo. The script asks for sudo itself, only on Linux and only to pin the
# toolbar icon, and the install still works if that is declined.

NO_PAUSE=false
for Arg in "$@"; do
    case "$Arg" in
        --no-pause) NO_PAUSE=true ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $Arg" >&2; exit 2 ;;
    esac
done

# This script and lib-gh-slash-extension.sh are in the scripts/ folder. The .crx is in its parent: the repo root, or the
# top of the release zip.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-gh-slash-extension.sh
source "$SCRIPT_DIR/lib-gh-slash-extension.sh" || { echo "ERROR: lib-gh-slash-extension.sh must be in the same folder as this script." >&2; exit 1; }

check_platform install-gh-slash-extension.bat
show_banner

# 1. Automatically find the most recently modified .crx
CRX_PATH=""
for Dir in "$SCRIPT_DIR" "$(dirname "$SCRIPT_DIR")"; do
    Latest="$(ls -t "$Dir/$CRX_PREFIX"*.crx 2>/dev/null | head -n 1)"
    if [ -n "$Latest" ]; then CRX_PATH="$Latest"; break; fi
done
if [ -z "$CRX_PATH" ]; then
    fail "No ${CRX_PREFIX}*.crx file found next to this script or in its parent folder. Keep the .crx in the folder you unzipped."
fi

# 2. Read the version from manifest.json inside the .crx (a .crx is a zip behind a small header; unzip warns about
#    that header but still extracts). Fall back to the version in the file name.
Version=""
if command -v unzip >/dev/null 2>&1 && command -v perl >/dev/null 2>&1; then
    Version="$(unzip -p "$CRX_PATH" manifest.json 2>/dev/null | perl -MJSON::PP -0777 -ne 'print decode_json($_)->{version}' 2>/dev/null)"
fi
if [ -z "$Version" ]; then
    Version="$(basename "$CRX_PATH" .crx)"; Version="${Version#"$CRX_PREFIX"}"
fi
case "$Version" in
    ''|*[!0-9.]*) fail "Could not work out the extension version from $CRX_PATH." ;;
esac
say "Detected $(basename "$CRX_PATH") -> Version $Version" "$C_CYAN"

# Decide which browsers to set up. If none is found, set up Chrome so it works once Chrome is installed.
TARGETS=()
for Variant in $(all_variants); do
    if variant_installed "$Variant"; then TARGETS+=("$Variant"); fi
done
if [ "${#TARGETS[@]}" -eq 0 ]; then
    TARGETS=(chrome)
    say "Google Chrome wasn't found on this computer. Setting up for it anyway; start Chrome once it is installed." "$C_YELLOW"
fi
for Variant in "${TARGETS[@]}"; do say "Setting up $(variant_label "$Variant")" "$C_CYAN"; done
if [ "$OS" = linux ] && { [ -d "$HOME/snap/chromium" ] || [ -d "$HOME/.var/app/org.chromium.Chromium" ]; }; then
    say "Note: Chromium installed as a snap or Flatpak keeps its files elsewhere and is not supported by this script." "$C_YELLOW"
fi

choose_install_mode "${TARGETS[@]}"  # before closing anything
if $SYSTEM_MODE; then  # make sure we can get administrator rights before closing or changing anything
    init_sudo
    "${SUDO[@]}" -v || fail "Administrator rights are needed. Nothing was changed."
fi

# 3. The browsers must be closed: they rewrite their Preferences files when they exit, which would undo the cleanup
#    in step 4. Offer to close them, or stop.
close_running_browsers     "is running and must be closed to finish the install."     "Close it now? It will be reopened with your tabs when the install finishes (y/n)"     "Try again (y/n)? Choose n to close it yourself"     "${TARGETS[@]}" || fail "Close the browser completely (all windows), then run this installer again. Nothing was changed."

# 4. Scan ALL profiles for the current user and clear the extension's blacklist entries
#    (the browser remembers an extension the user removed and refuses to install it again).
CLEAN_PREFS='
use strict; use warnings; use JSON::PP;
my ($file, $id) = @ARGV;
open my $in, "<:raw", $file or die "cannot read $file: $!";
my $raw = do { local $/; <$in> }; close $in;
my $json = JSON::PP->new->utf8->allow_nonref->allow_bignum;
my $data = $json->decode($raw);
my $modified = 0;
my $ext = ref $data eq "HASH" ? $data->{extensions} : undef;
if (ref $ext eq "HASH") {
    if (ref $ext->{settings} eq "HASH" && exists $ext->{settings}{$id}) { delete $ext->{settings}{$id}; $modified = 1; }
    if (ref $ext->{external_uninstalls} eq "ARRAY") {
        my @kept = grep { $_ ne $id } @{ $ext->{external_uninstalls} };
        if (@kept != @{ $ext->{external_uninstalls} }) { $ext->{external_uninstalls} = \@kept; $modified = 1; }
    }
}
if ($modified) {
    open my $out, ">:raw", $file or die "cannot write $file: $!";
    print $out $json->encode($data); close $out;
    print "modified\n";
}
'
for Variant in "${TARGETS[@]}"; do
    DataDir="$(variant_data_dir "$Variant")"
    if $SYSTEM_MODE; then
        say "Skipping the check for a previous removal of the extension; it needs the files macOS is blocking." "$C_YELLOW"
    elif [ ! -d "$DataDir" ]; then
        say "No $(variant_label "$Variant") profile folder found at $DataDir (has it been opened at least once?)." "$C_YELLOW"
    elif ! command -v perl >/dev/null 2>&1; then
        say "perl was not found, so the $(variant_label "$Variant") profiles were not checked for a previous removal of the extension." "$C_YELLOW"
    else
        for ProfileDir in "$DataDir"/Default "$DataDir"/Profile\ *; do
            [ -d "$ProfileDir" ] || continue
            for File in "$ProfileDir/Preferences" "$ProfileDir/Secure Preferences"; do
                [ -f "$File" ] || continue
                if ! cp -f "$File" "$File.bak"; then  # never edit a file we couldn't back up
                    say "Couldn't back up $File, so it was left as it is." "$C_YELLOW"
                    continue
                fi
                Result="$(perl -MJSON::PP -e "$CLEAN_PREFS" "$File" "$EXTENSION_ID" 2>/dev/null)"
                if [ "$Result" = modified ]; then
                    say "Cleared blacklist entry in $(variant_label "$Variant") [$(basename "$ProfileDir")] -> $(basename "$File")" "$C_YELLOW"
                fi
            done
        done
    fi
done

# 5. Register the .crx (per user, so no administrator rights are needed)
#    ...or, if macOS blocked that, for all users: keep a copy of the .crx where Chrome can always read it and
#    register that.
if $SYSTEM_MODE; then
    SYSTEM_CRX="$SYSTEM_CRX_DIR/$(basename "$CRX_PATH")"
    JsonTmp="$(mktemp)"
    printf '{\n  "external_crx": "%s",\n  "external_version": "%s"\n}\n' "$(json_escape "$SYSTEM_CRX")" "$Version" > "$JsonTmp"
    if "${SUDO[@]}" mkdir -p "$SYSTEM_CRX_DIR" "$(dirname "$SYSTEM_EXT_JSON")" \
        && "${SUDO[@]}" install -m 644 "$CRX_PATH" "$SYSTEM_CRX" \
        && "${SUDO[@]}" install -m 644 "$JsonTmp" "$SYSTEM_EXT_JSON"; then
        # drop the copies of older versions
        for File in "$SYSTEM_CRX_DIR/$CRX_PREFIX"*.crx; do
            [ -f "$File" ] && [ "$File" != "$SYSTEM_CRX" ] && "${SUDO[@]}" rm -f "$File"
        done
        say "Registered for every user of this Mac (copy of the .crx kept in $SYSTEM_CRX_DIR)." "$C_CYAN"
    else
        rm -f "$JsonTmp"
        fail "Couldn't write to /Library. Nothing is registered."
    fi
    rm -f "$JsonTmp"
fi
for Variant in "${TARGETS[@]}"; do
    $SYSTEM_MODE && break
    mkdir -p "$(dirname "$(ext_json "$Variant")")" || fail "Could not create $(dirname "$(ext_json "$Variant")")"
    printf '{\n  "external_crx": "%s",\n  "external_version": "%s"\n}\n' "$(json_escape "$CRX_PATH")" "$Version" > "$(ext_json "$Variant")" \
        || fail "Could not write $(ext_json "$Variant")"
done

#    ...and, on Linux, pin the toolbar icon with a browser policy (these files need root). On macOS the same policy
#    would have to come from a configuration profile, which could clash with ones your organization manages, so we
#    leave the icon unpinned there.
UNPINNED=false
if [ "$OS" = mac ]; then
    UNPINNED=true
else
    PolicyTmp="$(mktemp)"
    printf '{\n  "ExtensionSettings": {\n    "%s": {\n      "installation_mode": "allowed",\n      "toolbar_pin": "force_pinned"\n    }\n  }\n}\n' "$EXTENSION_ID" > "$PolicyTmp"
    init_sudo; if ! $NO_PAUSE; then say "Pinning the toolbar icon needs administrator rights (sudo)." "$C_YELLOW"; fi
    for Variant in "${TARGETS[@]}"; do
        if ! { "${SUDO[@]}" mkdir -p "$(variant_policy_dir "$Variant")" && "${SUDO[@]}" install -m 644 "$PolicyTmp" "$(policy_file "$Variant")"; }; then
            say "Couldn't write $(policy_file "$Variant"), so the $(variant_label "$Variant") toolbar icon is not pinned. The extension is still installed." "$C_YELLOW"
            UNPINNED=true
        fi
    done
    rm -f "$PolicyTmp"
fi

say "
Successfully registered $EXTENSION_ID v$Version!" "$C_GREEN"

reopen_closed
if [ "${#CLOSED[@]}" -eq 0 ]; then
    NEXT="Open (or restart) the browser -> go to chrome://extensions -> toggle the extension ON once."
elif $REOPEN_FAILED; then
    NEXT="Open the browser -> go to chrome://extensions -> toggle the extension ON once."
else
    NEXT="In the browser, go to chrome://extensions -> toggle the extension ON once."
fi
say "Next steps: $NEXT" "$C_CYAN"
if $UNPINNED; then
    say "Tip: pin the icon yourself with the puzzle-piece button in the browser's toolbar." "$C_CYAN"
fi
wait_for_enter "
Press Enter to close this window"
