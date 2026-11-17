# Shared by install-gh-slash-extension.sh and uninstall-gh-slash-extension.sh (macOS and Linux); sourced, not run.
# shellcheck shell=bash
# shellcheck disable=SC2034  # variables set here are used by the scripts that source this file

# --- What we install ---
EXTENSION_ID="aimpmkmhbohibcafaapmdhpmpmmofnpp"
CRX_PREFIX="gh-slash-autocomplete-"
POLICY_NAME="gh-slash-autocomplete.json"  # Linux only

# --- Output helpers (colors only when writing to a terminal) ---
if [ -t 1 ]; then
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_GRAY=$'\033[90m'; C_WHITE=$'\033[97m'; C_OFF=$'\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_GRAY=''; C_WHITE=''; C_OFF=''
fi
say()   { printf '%s%s%s\n' "$2" "$1" "$C_OFF"; }
fail()  { printf '%sERROR: %s%s\n' "$C_RED" "$1" "$C_OFF" >&2; exit 1; }
wait_for_enter() { if ! $NO_PAUSE; then read -r -p "$1" _ || true; fi; }
read_yes_no() {  # one key press, no Enter; asks until it is y or n; returns 0 for y. End of input counts as n.
    local Key
    while true; do
        printf '%s ' "$1"
        read -r -n 1 Key || { echo; return 1; }
        echo
        case "$Key" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
        esac
        say "Please press y or n." "$C_YELLOW"
    done
}
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

show_banner() {  # unless --no-pause: the extension's icon (a dark tile with a slash) in ASCII, so the output starts lower in the window
    $NO_PAUSE && return
    printf '%s' "$C_GRAY"
    cat <<'BANNER'
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
BANNER
    printf '%s' "$C_OFF"
    say "  GitHub bot slash-command autocomplete
" "$C_WHITE"
}

# --- Platform and browsers ---
# $1 is the name of the .bat file to point Windows users to.
check_platform() {
    case "$(uname -s)" in
        Darwin) OS=mac ;;
        Linux)  OS=linux; CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}" ;;
        *) fail "This script is for macOS and Linux. On Windows use $1." ;;
    esac
    if [ "$(id -u)" -eq 0 ]; then
        fail "Run this script as your normal user, not as root or with sudo. It asks for sudo itself when it needs it."
    fi
}

# The browsers this script knows about: "chrome" everywhere, "chromium" on Linux only.
# These give each one's name, profile folder, policy folder, process names and launch commands.
variant_label()      { if [ "$1" = chromium ]; then echo "Chromium"; else echo "Google Chrome"; fi; }
variant_data_dir()   {
    if [ "$OS" = mac ]; then echo "$HOME/Library/Application Support/Google/Chrome"
    elif [ "$1" = chromium ]; then echo "$CONFIG_HOME/chromium"
    else echo "$CONFIG_HOME/google-chrome"; fi
}
variant_policy_dir() { if [ "$1" = chromium ]; then echo "/etc/chromium/policies/managed"; else echo "/etc/opt/chrome/policies/managed"; fi; }  # Linux only
variant_procs()      { if [ "$1" = chromium ]; then echo "chromium chromium-browser"; else echo "chrome"; fi; }                              # Linux only
variant_bins()       { if [ "$1" = chromium ]; then echo "chromium chromium-browser"; else echo "google-chrome-stable google-chrome"; fi; } # Linux only
ext_json()           { echo "$(variant_data_dir "$1")/External Extensions/$EXTENSION_ID.json"; }
policy_file()        { echo "$(variant_policy_dir "$1")/$POLICY_NAME"; }                                                                    # Linux only
variant_installed() {  # a profile folder or a launch command exists for this browser
    local Bin
    [ -d "$(variant_data_dir "$1")" ] && return 0
    if [ "$OS" = linux ]; then
        for Bin in $(variant_bins "$1"); do command -v "$Bin" >/dev/null 2>&1 && return 0; done
    fi
    return 1
}
all_variants() { if [ "$OS" = mac ]; then echo chrome; else echo "chrome chromium"; fi; }

# macOS only: the system-wide folder Chrome also reads. If the per-user folder is blocked we register here instead,
# keeping our own copy of the .crx in SYSTEM_CRX_DIR. Writing either needs administrator rights.
SYSTEM_EXT_JSON="/Library/Application Support/Google/Chrome/External Extensions/$EXTENSION_ID.json"
SYSTEM_CRX_DIR="/Library/Application Support/gh-slash-autocomplete"

init_sudo() { if $NO_PAUSE; then SUDO=(sudo -n); else SUDO=(sudo); fi; }  # sudo asks for the password only when interactive

can_write_user_folder() {  # can we change the External Extensions folder of browser $1? (creates it if needed)
    local Dir Probe
    Dir="$(dirname "$(ext_json "$1")")"
    Probe="$Dir/.gh-slash-write-test.$$"
    if mkdir -p "$Dir" 2>/dev/null && : > "$Probe" 2>/dev/null; then rm -f "$Probe"; return 0; fi
    return 1
}
explain_blocked() {  # how to fix a blocked per-user folder
    if [ "$OS" = mac ]; then
        say "macOS is blocking this terminal from changing Chrome's files ('Operation not permitted'). To allow it:" "$C_YELLOW"
        say "  1. Open System Settings -> Privacy & Security -> Full Disk Access." "$C_YELLOW"
        say "  2. Switch on the terminal app you are running this in (Terminal, iTerm, ...). If it isn't listed, click + and add it." "$C_YELLOW"
        say "  3. Quit that terminal app completely (Cmd+Q), open it again, and re-run this script." "$C_YELLOW"
        say "If it still fails, this Mac may be managed by your organization; ask your IT team." "$C_YELLOW"
    else
        say "Check that your user owns that folder and that it isn't read-only." "$C_YELLOW"
    fi
}

# Uninstall: check, before anything is closed or removed, that we can change the folder of each browser among "$@".
check_can_write() {
    local V
    for V in "$@"; do
        can_write_user_folder "$V" && continue
        say "Can't change files in $(dirname "$(ext_json "$V")")" "$C_RED"
        explain_blocked
        fail "Nothing was changed."
    done
}

# Install: decide where to register, before anything is closed or changed. Sets SYSTEM_MODE=true when macOS blocks
# the per-user folder, so we use the system-wide one instead. Elsewhere a blocked folder stops the install.
choose_install_mode() {
    local V
    SYSTEM_MODE=false
    for V in "$@"; do
        can_write_user_folder "$V" && continue
        if [ "$OS" = mac ]; then
            say "macOS is blocking this terminal from changing Chrome's files ('Operation not permitted')." "$C_YELLOW"
            say "Installing for every user of this Mac instead; that asks for your administrator password." "$C_YELLOW"
            say "(To install just for you, give this terminal Full Disk Access and run this again.)" "$C_YELLOW"
            SYSTEM_MODE=true
        else
            say "Can't change files in $(dirname "$(ext_json "$V")")" "$C_RED"
            explain_blocked
            fail "Nothing was changed."
        fi
    done
}

# --- Browser process helpers ---
browser_pids() {  # the browser's own process(es) for variant $1, not its helpers
    local Name Pid Args
    if [ "$OS" = mac ]; then
        pgrep -u "$(id -u)" -x "Google Chrome"
    else
        for Name in $(variant_procs "$1"); do
            for Pid in $(pgrep -u "$(id -u)" -x "$Name"); do
                Args="$(ps -o args= -p "$Pid" 2>/dev/null)"
                case "$Args" in *--type=*) ;; *) echo "$Pid" ;; esac
            done
        done
    fi
}
running_among() {  # prints the variants among "$@" that are running
    local V
    for V in "$@"; do [ -n "$(browser_pids "$V")" ] && echo "$V"; done
}
close_browser() {  # same as clicking the X on each window; the browser shuts down normally and saves its state
    local Pid
    if [ "$OS" = mac ]; then
        osascript -e 'tell application "Google Chrome" to quit' >/dev/null 2>&1
    else
        for Pid in $(browser_pids "$1"); do kill -TERM "$Pid" 2>/dev/null; done
    fi
}
wait_for_browser() {  # wait_for_browser exit|start VARIANT SECONDS; returns 0 if the wanted state was reached
    local Want="$1" V="$2" Ticks=$(( $3 * 4 )) i
    for ((i = 0; i < Ticks; i++)); do
        if [ "$Want" = exit ] && [ -z "$(browser_pids "$V")" ]; then return 0; fi
        if [ "$Want" = start ] && [ -n "$(browser_pids "$V")" ]; then return 0; fi
        sleep 0.25
    done
    if [ "$Want" = exit ]; then [ -z "$(browser_pids "$V")" ]; else [ -n "$(browser_pids "$V")" ]; fi
}
reopen_browser() {  # reopen_browser VARIANT: launch with the previous tabs; retry, then return 0 if it is running
    local V="$1" Exe Name i
    for i in 1 2 3 4; do  # give it 3 seconds to show up each time, 4 attempts in all
        if [ "$OS" = mac ]; then
            open -a "Google Chrome" --args --restore-last-session >/dev/null 2>&1
        else
            Name="EXE_$V"; Exe="${!Name}"
            if [ -z "$Exe" ] || [ ! -x "$Exe" ]; then
                for Name in $(variant_bins "$V"); do Exe="$(command -v "$Name")" && break; done
            fi
            [ -n "$Exe" ] || return 1
            if command -v setsid >/dev/null 2>&1; then
                setsid "$Exe" --restore-last-session >/dev/null 2>&1 &
            else
                nohup "$Exe" --restore-last-session >/dev/null 2>&1 &
            fi
        fi
        wait_for_browser start "$V" 3 && return 0
    done
    return 1
}

# Offer to close the running browsers among "$@" the way the user would (asking them to quit, not killing them).
# $1 is the end of the "<browser> is running ..." message, $2 the question to close, $3 the question to retry.
# Sets CLOSED to the browsers we closed, which reopen_closed reopens later. Returns 1 if one is still running.
close_running_browsers() {
    local MsgRunning="$1" PromptClose="$2" PromptRetry="$3" V Pid Answer Still
    shift 3
    local -a Running=()
    CLOSED=()
    while IFS= read -r V; do [ -n "$V" ] && Running+=("$V"); done < <(running_among "$@")
    [ "${#Running[@]}" -gt 0 ] || return 0

    for V in "${Running[@]}"; do
        say "$(variant_label "$V") $MsgRunning" "$C_YELLOW"
        if [ "$OS" = linux ]; then  # remember what to launch again
            Pid="$(browser_pids "$V" | head -n 1)"
            printf -v "EXE_$V" '%s' "$(readlink "/proc/$Pid/exe" 2>/dev/null | sed 's/ (deleted)$//')"
        fi
    done
    Answer=false
    if ! $NO_PAUSE && read_yes_no "$PromptClose"; then Answer=true; fi

    while $Answer; do
        for V in "${Running[@]}"; do close_browser "$V"; done
        Still=true
        for V in "${Running[@]}"; do wait_for_browser exit "$V" 5 || Still=false; done
        $Still && break
        say "A browser didn't close. It may be waiting on a dialog or running in the background." "$C_YELLOW"
        read_yes_no "$PromptRetry" || Answer=false
    done

    [ -z "$(running_among "${Running[@]}")" ] || return 1
    sleep 1  # let it finish writing its files
    CLOSED=("${Running[@]}")
    say "Closed." "$C_CYAN"
}

# Reopen the browsers close_running_browsers closed. Sets REOPENED (any came back) and REOPEN_FAILED (any did not).
reopen_closed() {
    local V
    REOPENED=false; REOPEN_FAILED=false
    for V in "${CLOSED[@]}"; do
        if reopen_browser "$V"; then
            REOPENED=true
            say "Reopened $(variant_label "$V")." "$C_CYAN"
        else
            REOPEN_FAILED=true
            say "WARNING: Couldn't reopen $(variant_label "$V") automatically. Please start it yourself." "$C_YELLOW"
        fi
    done
}
