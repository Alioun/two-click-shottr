#!/bin/bash

repair_read() {
    if [[ ! -t 0 ]]; then
        printf 'This repair needs terminal input. No action was approved.\n' >&2
        return 1
    fi
    if ! read -r REPAIR_REPLY; then
        printf '\nInput closed. Repair stopped without approval.\n' >&2
        return 1
    fi
}

repair_confirm() {
    printf '  %s [Y/n] ' "$1"
    repair_read || return 1
    [[ -z "$REPAIR_REPLY" || "$REPAIR_REPLY" =~ ^[Yy]([Ee][Ss])?$ ]]
}

repair_pause() {
    printf '  %s ' "${1:-Press Enter to continue}"
    repair_read || return 1
}
