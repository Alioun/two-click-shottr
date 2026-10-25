#!/bin/bash

# security repeats identities in its matching and valid sections, with optional trust diagnostics.
resolve_signing_identity() {
    CODE_SIGN_IDENTITY="$1" IDENTITY_MATCH_MODE="${2:-unique}" awk '
        $1 ~ /^[0-9]+\)$/ && length($2) == 40 && $2 ~ /^[[:xdigit:]]+$/ {
            row = $0
            if (!match(row, /"[^"]*"/)) next
            label = substr(row, RSTART + 1, RLENGTH - 2)
            requested = ENVIRON["CODE_SIGN_IDENTITY"]
            hash = toupper($2)
            if (label == requested || (length(requested) == 40 && hash == toupper(requested))) {
                if (!seen[hash]++) { identity = hash; count++ }
            }
        }
        END {
            if (ENVIRON["IDENTITY_MATCH_MODE"] == "exists") exit (count == 0)
            if (count != 1) exit 1
            print identity
        }
    '
}

designated_requirement() {
    local output requirement
    output=$(codesign -d -r- "$1") || return 1
    requirement=$(printf '%s\n' "$output" | sed -n 's/^#\{0,1\} *designated => //p')
    [[ -n "$requirement" && "$requirement" != *$'\n'* ]] || return 1
    printf '%s\n' "$requirement"
}

stable_requirement() {
    local requirement
    requirement=$(designated_requirement "$1") || return 1
    [[ "$requirement" != *cdhash* && ( "$requirement" == *'certificate '* || "$requirement" == *'anchor '* ) ]] || {
        printf 'The signed app has no stable certificate requirement.\n' >&2
        return 1
    }
    printf '%s\n' "$requirement"
}

# Both renames stay on the destination filesystem. A failed copy never touches the live bundle.
replace_signed_app() (
    set -euo pipefail
    source="$1" destination="$2" requirement="$3" committed=0 candidate_ready=0
    transaction=
    mkdir -p "$(dirname "$destination")" || exit $?
    transaction=$(mktemp -d "$(dirname "$destination")/.two-click-replace.XXXXXX") || exit $?
    # shellcheck disable=SC2329
    cleanup_replacement() {
        local status=$?
        trap - EXIT HUP INT TERM
        if (( ! committed )); then
            if [[ -e "$transaction/previous.app" || -L "$transaction/previous.app" ]]; then
                rm -rf "$destination"
                if ! mv "$transaction/previous.app" "$destination"; then
                    printf 'Rollback failed. Previous app retained at %s/previous.app\n' "$transaction" >&2
                    exit 1
                fi
            elif (( candidate_ready )) && [[ ! -e "$transaction/candidate.app" && ! -L "$transaction/candidate.app" ]]; then
                rm -rf "$destination"
            fi
        fi
        rm -rf "$transaction"
        exit "$status"
    }
    trap cleanup_replacement EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    ditto "$source" "$transaction/candidate.app" || exit $?
    codesign --verify --strict -R "=$requirement" "$transaction/candidate.app" || exit $?
    candidate_ready=1
    if [[ -e "$destination" || -L "$destination" ]]; then
        mv "$destination" "$transaction/previous.app" || exit $?
    fi
    mv "$transaction/candidate.app" "$destination" || exit $?
    codesign --verify --strict -R "=$requirement" "$destination" || exit $?
    committed=1
)

reserve_signing_setup() {
    local state="$1"
    if [[ -e "$state" || -L "$state" ]]; then
        printf 'A prior signing import did not finish. No new key will be generated.\n' >&2
        printf 'Recover Two Click Shottr Local and its original private key in Keychain Access.\n' >&2
        printf 'If you deliberately discard the failed identity, remove this marker yourself before retrying:\n%s\n' "$state" >&2
        return 1
    fi
    mkdir -p "$(dirname "$state")" || return 1
    mkdir "$state"
}
