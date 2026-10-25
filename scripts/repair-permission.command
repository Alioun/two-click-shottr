#!/bin/bash
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd)
source "$scripts/signing-support.sh"
source "$scripts/repair-input.sh"

stage_index=0
stage() {
    stage_index=$((stage_index + 1))
    printf '\nStep %s/%s: %s\n' "$stage_index" "$TOTAL_STAGES" "$1"
}
say() { printf '  %s\n' "$1"; }
warn() { printf '  %s\n' "$1" >&2; }

run_wizard() {
TOTAL_STAGES=4
[[ -t 0 ]] || { warn "Run this repair in a terminal. No action was approved."; return 1; }
repo=$(cd "$(dirname "$0")/.." && pwd)
installed="$HOME/Applications/Two Click Shottr.app"
identity_name='Two Click Shottr Local'
repair_tmp=$(mktemp -d "${TMPDIR:-/tmp}/two-click-repair.XXXXXX")
trap 'rm -rf "$repair_tmp"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
umask 077

printf '\nRepair Two Click Shottr permission\n'
stage "Keep the app's identity stable"
say "Earlier builds changed the app's signature. macOS still remembers the old one."
say "This creates a local signing certificate in your default user keychain."
say "The private key stays on this Mac. Certificate trust settings are left unchanged."
say "Later builds reuse it, so updates can keep the same permission identity."
repair_confirm "Set up or reuse this app's local signing certificate?" || return 1
setup_state="$HOME/Library/Application Support/Two Click Shottr/signing-setup-pending"
keychain=$(security default-keychain -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')
if ! security find-certificate -c "$identity_name" -p "$keychain" > "$repair_tmp/signing.pem" 2>/dev/null; then
  if ! existing_identities=$(security find-identity -p codesigning "$keychain"); then
    warn "Could not inspect existing signing identities. No key will be generated."
    say "Unlock your default keychain in Keychain Access, then rerun."
    return 1
  fi
  if printf '%s\n' "$existing_identities" | resolve_signing_identity "$identity_name" exists >/dev/null; then
    warn "An existing identity was found but its certificate could not be read. No key will be generated."
    say "Check the default keychain and Two Click Shottr Local in Keychain Access, then rerun."
    return 1
  fi
  # A failed import can leave a nonextractable private key without its certificate.
  reserve_signing_setup "$setup_state" || return 1
  cat > "$repair_tmp/certificate.cnf" <<'CERT'
[req]
prompt = no
distinguished_name = subject
x509_extensions = signing
[subject]
CN = Two Click Shottr Local
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CERT
  /usr/bin/openssl req -new -newkey rsa:3072 -x509 -nodes -days 3650 \
    -config "$repair_tmp/certificate.cnf" -keyout "$repair_tmp/signing-key.pem" \
    -out "$repair_tmp/signing.pem" 2> "$repair_tmp/certificate.log"
  if ! security import "$repair_tmp/signing-key.pem" -k "$keychain" -f openssl -t priv -x -T /usr/bin/codesign ||
     ! security import "$repair_tmp/signing.pem" -k "$keychain" -t cert; then
    warn "Signing import did not finish. No automatic regeneration will occur."
    say "Inspect Two Click Shottr Local in Keychain Access and recover the original pair if possible."
    say "Rerun for recovery guidance. The installed app and certificate trust are unchanged."
    return 1
  fi
  rm -f "$repair_tmp/signing-key.pem"
fi
certificate_subject=$(/usr/bin/openssl x509 -in "$repair_tmp/signing.pem" -noout -subject -nameopt RFC2253 | sed 's/^subject=[[:space:]]*//')
if [[ "$certificate_subject" != "CN=$identity_name" ]]; then
  warn "A different certificate matched this name. Installation stopped."
  return 1
fi
signing_hash=$(/usr/bin/openssl x509 -in "$repair_tmp/signing.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
if ! security find-identity -p codesigning "$keychain" | resolve_signing_identity "$signing_hash" >/dev/null; then
  warn "The certificate and private key did not form a signing identity. The installed app is unchanged."
  say "Recover its original private key in Keychain Access, then rerun. This script never replaces an existing certificate."
  return 1
fi

[[ ! -d "$setup_state" ]] || rmdir "$setup_state"

stage "Build and replace the companion"
say "macOS may ask to let codesign use the local signing key. Approve it yourself."
CODE_SIGN_IDENTITY="$signing_hash" "$repo/scripts/build.sh"
app="$repo/dist/Two Click Shottr.app"
codesign --verify --strict "$app"
if ! requirement=$(stable_requirement "$app"); then
  warn "The new app lacks a stable certificate identity. Installation stopped."
  return 1
fi
# Check an update against the original requirement before replacing the installed app.
ditto "$app" "$repair_tmp/Update.app"
current_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
[[ "$current_build" =~ ^[0-9]+$ ]] || { warn "Build version must be numeric for the update check."; return 1; }
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((current_build + 1))" "$repair_tmp/Update.app/Contents/Info.plist"
codesign --force --sign "$signing_hash" --timestamp=none --identifier local.two-click-shottr "$repair_tmp/Update.app"
codesign --verify --strict -R "=$requirement" "$repair_tmp/Update.app"
say "The signed app and a simulated update both satisfy the same identity requirement."
repair_confirm "Replace the installed companion with this signed build?" || return 1
pkill -TERM -x TwoClickShottr 2>/dev/null || true
for ((attempt=0; attempt<30; attempt++)); do
  pgrep -x TwoClickShottr >/dev/null || break
  sleep 0.1
done
if pgrep -x TwoClickShottr >/dev/null; then
  warn "Quit Two Click Shottr from its menu, then rerun this script."
  return 1
fi
if [[ -d "$installed" ]]; then
  backup_dir="$HOME/Library/Application Support/Two Click Shottr/Backups"
  mkdir -p "$backup_dir"
  backup_run=$(mktemp -d "$backup_dir/before-permission-repair-$(date +%Y%m%d-%H%M%S).XXXXXX")
  ditto -c -k --keepParent "$installed" "$backup_run/Two Click Shottr.zip"
fi
replace_signed_app "$app" "$installed" "$requirement"
say "Installed. Your saved shortcut and selection preferences are preserved."

stage "Replace the stale privacy grant"
diagnose_status=0
"$repo/scripts/verify-installed.sh" --diagnose --app "$installed" || diagnose_status=$?
if (( diagnose_status != 0 && diagnose_status != 1 )); then
  warn "Installed-app diagnosis could not complete. No privacy grant was changed."
  return "$diagnose_status"
fi
if (( diagnose_status == 0 )); then
  say "The newly installed app already has permission. Keeping its grant."
else
say "Only Two Click Shottr's Screen Recording grant will be cleared."
repair_confirm "Clear its stale grant so you can allow the newly signed app?" || return 1
tccutil reset ScreenCapture local.two-click-shottr
open "$installed"
open -b com.apple.systempreferences
say "Choose Capture in Two Click Shottr's menu, or press Shift+Command+4."
say "Allow Two Click Shottr in Screen Recording settings."
say "macOS may call it Screen & System Audio Recording."
say "Approve Quit & Reopen if macOS offers it."
repair_pause "Press Enter after allowing access."
fi

stage "Verify the installed app"
# LaunchServices checks the app's permission, rather than the terminal's inherited permission.
pkill -TERM -x TwoClickShottr 2>/dev/null || true
sleep 1
diagnose_status=0
"$repo/scripts/verify-installed.sh" --diagnose --app "$installed" || diagnose_status=$?
if (( diagnose_status != 0 && diagnose_status != 1 )); then
  warn "Installed-app diagnosis could not complete. Repair is not complete."
  return "$diagnose_status"
fi
if (( diagnose_status == 1 )); then
  warn "The installed app still reports no permission. Repair is not complete."
  open "$installed"
  open -b com.apple.systempreferences
  say "Remove Two Click Shottr with the minus button, add this installed app again, and allow it."
  say "$installed"
  say "Then rerun this script. It will reuse the signing certificate."
  return 1
fi
say "The installed app reports Screen Recording permission granted."
say "The next check briefly shows a test rectangle and opens its capture in Shottr."
repair_pause "Press Enter to check capture and Shottr handoff."
if ! "$repo/scripts/verify-installed.sh" --capture --app "$installed"; then
  warn "The installed-app capture check did not complete successfully."
  open "$installed"
  return 1
fi
open "$installed"
printf '\nSetup complete.\n'
say "Permission, captured pixels, and opening in Shottr all passed."
say "Use Shift+Command+4 to select an area with two clicks."
}

run_wizard "$@"; exit
