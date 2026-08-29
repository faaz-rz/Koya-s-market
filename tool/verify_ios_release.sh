#!/usr/bin/env bash
set -euo pipefail

artifact_path="${1:-}"
if [[ -z "$artifact_path" || ! -e "$artifact_path" ]]; then
  printf 'Usage: %s /path/to/KoyaStores.ipa-or-Runner.app\n' "$0" >&2
  exit 64
fi

temporary_directory=""
cleanup() {
  if [[ -n "$temporary_directory" && -d "$temporary_directory" ]]; then
    rm -rf "$temporary_directory"
  fi
}
trap cleanup EXIT

case "$artifact_path" in
  *.ipa)
    temporary_directory="$(mktemp -d)"
    /usr/bin/ditto -x -k "$artifact_path" "$temporary_directory"
    app_path="$(find "$temporary_directory/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
    ;;
  *.app)
    app_path="$artifact_path"
    ;;
  *)
    printf 'error: Expected an .ipa or .app artifact: %s\n' "$artifact_path" >&2
    exit 64
    ;;
esac

if [[ -z "${app_path:-}" || ! -d "$app_path" ]]; then
  printf 'error: Could not locate the application bundle in %s.\n' "$artifact_path" >&2
  exit 1
fi

info_plist="$app_path/Info.plist"
privacy_manifest="$app_path/PrivacyInfo.xcprivacy"
plist_buddy=/usr/libexec/PlistBuddy
expected_bundle_id="${KOYAS_IOS_BUNDLE_ID:-com.koyas.koyasSupermarket}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
pubspec_version="$(awk '/^version: / { print $2; exit }' "$repo_root/pubspec.yaml")"
expected_version="${pubspec_version%%+*}"
expected_build="${pubspec_version##*+}"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

read_plist() {
  "$plist_buddy" -c "Print :$1" "$info_plist" 2>/dev/null
}

[[ -f "$info_plist" ]] || fail 'Info.plist is missing from the app bundle.'
[[ -f "$privacy_manifest" ]] || fail 'PrivacyInfo.xcprivacy is missing from the app bundle.'
/usr/bin/plutil -lint "$info_plist" "$privacy_manifest" >/dev/null

while IFS= read -r embedded_privacy_manifest; do
  /usr/bin/plutil -lint "$embedded_privacy_manifest" >/dev/null ||
    fail "Invalid embedded privacy manifest: $embedded_privacy_manifest."
  embedded_privacy_xml="$(/usr/bin/plutil -convert xml1 -o - "$embedded_privacy_manifest")"
  embedded_tracking="$(/usr/bin/plutil -extract NSPrivacyTracking raw -o - "$embedded_privacy_manifest" 2>/dev/null || true)"
  [[ "$embedded_tracking" != "true" ]] ||
    fail "An embedded SDK declares tracking: $embedded_privacy_manifest."
  [[ "$embedded_privacy_xml" != *'<string>Email address</string>'* ]] ||
    fail "An embedded privacy manifest contains a nonstandard collected-data value: $embedded_privacy_manifest."
  if [[ "$embedded_privacy_manifest" != "$privacy_manifest" &&
        "$embedded_privacy_xml" == *'<key>NSPrivacyCollectedDataType</key>'* ]]; then
    fail "An embedded SDK declares collected data that is not covered by the first-release worksheet: $embedded_privacy_manifest."
  fi
done < <(find "$app_path" -name PrivacyInfo.xcprivacy -type f -print)

[[ "$(read_plist CFBundleIdentifier)" == "$expected_bundle_id" ]] ||
  fail "Unexpected bundle identifier: $(read_plist CFBundleIdentifier)."
[[ "$(read_plist CFBundleDisplayName)" == "Koya Stores" ]] ||
  fail 'CFBundleDisplayName must be Koya Stores.'
[[ "$(read_plist CFBundleShortVersionString)" == "$expected_version" ]] ||
  fail "Expected version $expected_version."
[[ "$(read_plist CFBundleVersion)" == "$expected_build" ]] ||
  fail "Expected build $expected_build."
[[ "$(read_plist MinimumOSVersion)" == "15.0" ]] ||
  fail 'MinimumOSVersion must be 15.0.'
[[ "$(read_plist CFBundleSupportedPlatforms:0)" == "iPhoneOS" ]] ||
  fail 'The artifact was not built for a physical iPhone.'
[[ "$(read_plist DTPlatformName)" == "iphoneos" ]] ||
  fail 'DTPlatformName must be iphoneos.'
[[ "$(read_plist UIDeviceFamily:0)" == "1" ]] ||
  fail 'The first release must target iPhone only (UIDeviceFamily 1).'
if "$plist_buddy" -c 'Print :UIDeviceFamily:1' "$info_plist" >/dev/null 2>&1; then
  fail 'Unexpected secondary device family; iPad is not supported in this release.'
fi
[[ "$(read_plist UISupportedInterfaceOrientations:0)" == "UIInterfaceOrientationPortrait" ]] ||
  fail 'The first supported phone orientation must be portrait.'
if "$plist_buddy" -c 'Print :UISupportedInterfaceOrientations:1' "$info_plist" >/dev/null 2>&1; then
  fail 'The first release must be portrait-only on iPhone.'
fi
[[ "$(read_plist ITSAppUsesNonExemptEncryption)" == "false" ]] ||
  fail 'ITSAppUsesNonExemptEncryption must be false.'

if "$plist_buddy" -c 'Print :NSBonjourServices' "$info_plist" >/dev/null 2>&1; then
  fail 'Release Info.plist contains the debug-only NSBonjourServices key.'
fi
if "$plist_buddy" -c 'Print :NSLocalNetworkUsageDescription' "$info_plist" >/dev/null 2>&1; then
  fail 'Release Info.plist contains the debug-only local-network description.'
fi
if "$plist_buddy" -c 'Print :UIBackgroundModes' "$info_plist" >/dev/null 2>&1; then
  fail 'Unexpected background modes are enabled in the first iOS release.'
fi

privacy_xml="$(/usr/bin/plutil -convert xml1 -o - "$privacy_manifest")"
for required_data_type in \
  NSPrivacyCollectedDataTypeEmailAddress \
  NSPrivacyCollectedDataTypeUserID \
  NSPrivacyCollectedDataTypeName \
  NSPrivacyCollectedDataTypePhoneNumber \
  NSPrivacyCollectedDataTypePhysicalAddress \
  NSPrivacyCollectedDataTypePurchaseHistory; do
  [[ "$privacy_xml" == *"$required_data_type"* ]] ||
    fail "Privacy manifest is missing $required_data_type."
done
[[ "$privacy_xml" != *'<string>Email address</string>'* ]] ||
  fail 'Privacy manifest contains a nonstandard collected-data value.'
[[ "$(/usr/bin/plutil -extract NSPrivacyTracking raw "$privacy_manifest")" == "false" ]] ||
  fail 'The first release must declare that it does not track users.'

if find "$app_path" -iname '*razorpay*' -print -quit | grep -q .; then
  fail 'The disabled Razorpay SDK is still present in the iOS bundle.'
fi
if find "$app_path" \( -iname '*firebase*' -o -iname 'GoogleService-Info.plist' \) -print -quit | grep -q .; then
  fail 'The disabled Firebase SDK or configuration is still present in the iOS bundle.'
fi
if find "$app_path" -iname '*file_picker*' -print -quit | grep -q .; then
  fail 'The web-admin-only file picker is unexpectedly present in the customer iOS bundle.'
fi

executable_name="$(read_plist CFBundleExecutable)"
[[ -x "$app_path/$executable_name" ]] || fail 'The app executable is missing.'
if command -v lipo >/dev/null 2>&1; then
  /usr/bin/lipo -info "$app_path/$executable_name" | grep -q 'arm64' ||
    fail 'The app executable does not contain arm64.'
fi

if /usr/bin/codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
  entitlements="$(/usr/bin/codesign -d --entitlements :- "$app_path" 2>/dev/null || true)"
  get_task_allow="$(printf '%s' "$entitlements" | /usr/bin/plutil -extract get-task-allow raw -o - - 2>/dev/null || true)"
  aps_environment="$(printf '%s' "$entitlements" | /usr/bin/plutil -extract aps-environment raw -o - - 2>/dev/null || true)"
  [[ "$get_task_allow" != "true" ]] || fail 'Release signing contains get-task-allow=true.'
  [[ -z "$aps_environment" ]] || fail 'Push entitlement is unexpectedly enabled in the first release.'
else
  [[ "${ALLOW_UNSIGNED_IOS_VERIFY:-false}" == "true" ]] ||
    fail 'Code signature verification failed. Use a signed archive/IPA for final verification.'
fi

printf 'Verified iOS artifact: %s\n' "$artifact_path"
printf 'Bundle: %s · Version: %s (%s) · iPhone · iOS 15+ · no tracking · pay at handover\n' \
  "$expected_bundle_id" "$expected_version" "$expected_build"
