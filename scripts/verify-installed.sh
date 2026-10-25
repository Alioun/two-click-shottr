#!/bin/bash
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd)
source "$scripts/verification-support.sh"
usage() {
    printf 'Usage: %s --diagnose|--capture [--app /absolute/installed.app]\n' "$0" >&2
    printf 'Diagnosis never requests permission. Capture requires an existing grant and opens a test capture in Shottr.\n' >&2
}
[[ $# -ge 1 ]] || { usage; exit 2; }
mode="$1"
shift
case "$mode" in --diagnose|--capture) ;; *) usage; exit 2 ;; esac
installed="$HOME/Applications/Two Click Shottr.app"
if [[ $# -gt 0 ]]; then
    [[ $# -eq 2 && "$1" == --app && "$2" == /* ]] || { usage; exit 2; }
    installed="$2"
fi
report_dir=$(mktemp -d "${TMPDIR:-/tmp}/two-click-verify.XXXXXX")
trap 'rm -rf "$report_dir"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
permission=$(launch_installed_report "$installed" --diagnose "$report_dir/diagnose.json" screenCapturePermission 100) || exit $?
if [[ "$mode" == --diagnose ]]; then
    cat "$report_dir/diagnose.json"
fi
if [[ "$permission" != true ]]; then
    printf 'Screen Recording permission is denied for the installed app. No permission was requested.\n' >&2
    exit 1
fi
if [[ "$mode" == --capture ]]; then
    passed=$(launch_installed_report "$installed" --verify-capture "$report_dir/capture.json" passed 200) || exit $?
    cat "$report_dir/capture.json"
    [[ "$passed" == true ]] || { printf 'The installed app capture verifier reported failure.\n' >&2; exit 1; }
fi
