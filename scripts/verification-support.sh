#!/bin/bash

report_boolean() {
    /usr/bin/plutil -extract "$2" raw -expect bool -o - "$1" 2>/dev/null
}

# False is a complete report. Only missing, partial, or malformed output keeps polling.
wait_for_report() {
    local file="$1" field="$2" attempts="$3" value attempt
    for ((attempt=0; attempt<attempts; attempt++)); do
        if value=$(report_boolean "$file" "$field"); then
            case "$value" in
                true|false) printf '%s\n' "$value"; return 0 ;;
            esac
        fi
        sleep 0.1
    done
    printf 'Timed out waiting for a complete %s report. The app may have exited without a report.\n' "$field" >&2
    return 3
}

launch_installed_report() {
    local installed="$1" mode="$2" report="$3" field="$4" attempts="$5"
    [[ -d "$installed" ]] || { printf 'Installed app not found at %s\n' "$installed" >&2; return 4; }
    # -n isolates diagnostics from an already running menu app. No direct executable launch.
    open -n --stdout "$report" "$installed" --args "$mode" || {
        printf 'LaunchServices could not launch %s.\n' "$installed" >&2
        return 4
    }
    wait_for_report "$report" "$field" "$attempts"
}
