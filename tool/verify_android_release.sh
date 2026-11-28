#!/usr/bin/env bash
set -euo pipefail

artifact_path="${1:-}"
expected_application_id="com.koyas.koyas_supermarket"
expected_target_sdk="36"
if [[ -z "$artifact_path" || ! -f "$artifact_path" ]]; then
  echo "Usage: tool/verify_android_release.sh <release.apk|release.aab>" >&2
  exit 2
fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
export LC_ALL=C
normalize_fingerprint() {
  tr -d ':\r' | tr '[:upper:]' '[:lower:]'
}
expected_fingerprint="$(openssl x509 -in "$repo_root/android/koyas-upload-certificate.pem" \
  -noout -fingerprint -sha256 | cut -d= -f2 | normalize_fingerprint)"
pubspec_version="$(awk '/^version: / { print $2; exit }' "$repo_root/pubspec.yaml")"
if [[ ! "$pubspec_version" =~ ^[^+]+\+[0-9]+$ ]]; then
  echo "Expected a version and build number in pubspec.yaml." >&2
  exit 1
fi
expected_version_code="${pubspec_version##*+}"
expected_version_name="${pubspec_version%%+*}"

if ! java -version >/dev/null 2>&1 &&
  [[ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

case "$artifact_path" in
  *.apk)
    android_sdk_path="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
    if [[ -z "$android_sdk_path" && -f "$repo_root/android/local.properties" ]]; then
      android_sdk_path="$(sed -n 's/^sdk.dir=//p' "$repo_root/android/local.properties" | head -1)"
    fi
    if [[ -z "$android_sdk_path" ]]; then
      echo "ANDROID_HOME or ANDROID_SDK_ROOT is required to locate apksigner." >&2
      exit 2
    fi
    apksigner_path="$(find "$android_sdk_path/build-tools" -name apksigner -type f | sort -V | tail -1)"
    if [[ -z "$apksigner_path" ]]; then
      echo "apksigner was not found in Android build-tools." >&2
      exit 2
    fi
    certificate_output="$($apksigner_path verify --verbose --print-certs "$artifact_path")"
    if grep -qiE 'CN=Android Debug|O=Android, CN=Android Debug' <<<"$certificate_output"; then
      echo "Refusing debug-signed release APK." >&2
      exit 1
    fi
    grep -q 'Verified using v2 scheme.*true' <<<"$certificate_output"
    actual_fingerprint="$(awk '/^Signer #[0-9]+ certificate SHA-256 digest:/ {print $NF}' \
      <<<"$certificate_output" | normalize_fingerprint)"

    apkanalyzer_path="$(find "$android_sdk_path/cmdline-tools" -path '*/bin/apkanalyzer' -type f | sort -V | tail -1)"
    if [[ -z "$apkanalyzer_path" ]]; then
      echo "apkanalyzer was not found in Android command-line tools." >&2
      exit 2
    fi
    application_id="$($apkanalyzer_path manifest application-id "$artifact_path")"
    target_sdk="$($apkanalyzer_path manifest target-sdk "$artifact_path")"
    version_code="$($apkanalyzer_path manifest version-code "$artifact_path")"
    version_name="$($apkanalyzer_path manifest version-name "$artifact_path")"
    permissions="$($apkanalyzer_path manifest permissions "$artifact_path")"
    debuggable="$($apkanalyzer_path manifest debuggable "$artifact_path")"
    cleartext="$($apkanalyzer_path manifest print "$artifact_path" | \
      sed -nE 's/.*android:usesCleartextTraffic="([^"]+)".*/\1/p')"
    if ! "$(dirname "$apksigner_path")/zipalign" -c -P 16 4 "$artifact_path"; then
      echo "APK failed the 16 KB native library ZIP alignment check." >&2
      exit 1
    fi
    ;;
  *.aab)
    # Upload keys are normally self-signed, so cryptographic verification must
    # not use jarsigner's -strict certificate-chain policy.
    if ! verification_output="$(jarsigner -verify -verbose -certs "$artifact_path" 2>&1)"; then
      echo "App bundle signature verification failed." >&2
      exit 1
    fi
    if ! grep -qi 'jar verified' <<<"$verification_output" ||
        grep -qi 'contains unsigned entries' <<<"$verification_output"; then
      echo "App bundle must be fully signed." >&2
      exit 1
    fi
    if grep -qi 'CN=Android Debug' <<<"$verification_output"; then
      echo "Refusing debug-signed release app bundle." >&2
      exit 1
    fi
    actual_fingerprint="$(keytool -printcert -jarfile "$artifact_path" | \
      awk '/^[[:space:]]*SHA256:/ && !found++ {print $NF}' | normalize_fingerprint)"

    if [[ -n "${BUNDLETOOL_JAR:-}" && -f "$BUNDLETOOL_JAR" ]]; then
      bundletool_command=(java -jar "$BUNDLETOOL_JAR")
    elif command -v bundletool >/dev/null 2>&1; then
      bundletool_command=(bundletool)
    else
      echo "Bundletool is required to inspect an AAB. Install the official bundletool executable or set BUNDLETOOL_JAR to bundletool-all.jar." >&2
      exit 2
    fi
    bundle_manifest_value() {
      "${bundletool_command[@]}" dump manifest \
        --bundle="$artifact_path" \
        --xpath="$1"
    }
    application_id="$(bundle_manifest_value '/manifest/@package')"
    target_sdk="$(bundle_manifest_value '/manifest/uses-sdk/@android:targetSdkVersion')"
    version_code="$(bundle_manifest_value '/manifest/@android:versionCode')"
    version_name="$(bundle_manifest_value '/manifest/@android:versionName')"
    manifest="$("${bundletool_command[@]}" dump manifest --bundle="$artifact_path")"
    permissions="$(grep -E '<uses-permission[ >]' <<<"$manifest")"
    debuggable="$(bundle_manifest_value '/manifest/application/@android:debuggable' 2>/dev/null || true)"
    cleartext="$(bundle_manifest_value '/manifest/application/@android:usesCleartextTraffic')"
    "${bundletool_command[@]}" validate --bundle="$artifact_path" >/dev/null
    bundle_config="$("${bundletool_command[@]}" dump config --bundle="$artifact_path")"
    if ! grep -q 'PAGE_ALIGNMENT_16K' <<<"$bundle_config"; then
      echo "App bundle does not request 16 KB ZIP alignment for generated APKs." >&2
      exit 1
    fi
    ;;
  *)
    echo "Expected an .apk or .aab artifact." >&2
    exit 2
    ;;
esac

if [[ ! "$expected_fingerprint" =~ ^[a-f0-9]{64}$ || "$actual_fingerprint" != "$expected_fingerprint" ]]; then
  echo "Signing certificate does not match android/koyas-upload-certificate.pem." >&2
  exit 1
fi
if [[ "$application_id" != "$expected_application_id" ]]; then
  echo "Unexpected application ID: $application_id" >&2
  exit 1
fi
if [[ "$target_sdk" != "$expected_target_sdk" ]]; then
  echo "Expected target SDK $expected_target_sdk, found $target_sdk." >&2
  exit 1
fi
if [[ "$version_code" != "$expected_version_code" || "$version_name" != "$expected_version_name" ]]; then
  echo "Expected version $expected_version_name ($expected_version_code), found $version_name ($version_code)." >&2
  exit 1
fi
if ! grep -q 'android.permission.INTERNET' <<<"$permissions"; then
  echo "Release artifact is missing android.permission.INTERNET." >&2
  exit 1
fi
if [[ "$debuggable" == "true" ]]; then
  echo "Refusing a debuggable release artifact." >&2
  exit 1
fi
if [[ "$cleartext" != "false" ]]; then
  echo "The release must explicitly disallow cleartext traffic." >&2
  exit 1
fi
if grep -qE 'android\.permission\.(ACCESS_BACKGROUND_LOCATION|MANAGE_EXTERNAL_STORAGE|QUERY_ALL_PACKAGES|REQUEST_INSTALL_PACKAGES|USE_FULL_SCREEN_INTENT|READ_MEDIA_IMAGES|READ_MEDIA_VIDEO)|com\.google\.android\.gms\.permission\.AD_ID' <<<"$permissions"; then
  echo "The release requests a permission outside the intended Play declarations." >&2
  exit 1
fi

python3 - "$artifact_path" <<'PY'
import re
import struct
import sys
import zipfile

artifact = sys.argv[1]
with zipfile.ZipFile(artifact) as archive:
    libraries = [name for name in archive.namelist()
                 if re.fullmatch(r'(?:[^/]+/)?lib/(?:arm64-v8a|x86_64)/[^/]+\.so', name)]
    if artifact.endswith('.aab') and 'base/lib/arm64-v8a/libapp.so' not in libraries:
        sys.exit('App bundle is missing the ARM64 Flutter app library.')
    for name in libraries:
        data = archive.read(name)
        if not data.startswith(b'\x7fELF\x02\x01'):
            sys.exit(f'Expected a little-endian 64-bit ELF library: {name}')
        program_offset = struct.unpack_from('<Q', data, 32)[0]
        entry_size, entry_count = struct.unpack_from('<HH', data, 54)
        loads = 0
        for index in range(entry_count):
            segment = struct.unpack_from('<IIQQQQQQ', data, program_offset + index * entry_size)
            segment_type, _, file_offset, virtual_address, _, _, _, alignment = segment
            if segment_type == 1:
                loads += 1
                if alignment < 16384 or (file_offset - virtual_address) % 16384:
                    sys.exit(f'Native library is not 16 KB aligned: {name}')
        if loads == 0:
            sys.exit(f'Native library has no loadable segments: {name}')
    print(f'16 KB ELF alignment verified for {len(libraries)} 64-bit native libraries.')
PY

echo "Android release verified: $application_id $version_name ($version_code), target SDK $target_sdk, signed and non-debuggable."
