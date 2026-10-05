#!/usr/bin/env bash
set -euo pipefail

artifact_path="${1:-}"
expected_application_id="com.koyas.koyas_supermarket"
expected_target_sdk="36"
expected_version_code="11"
expected_version_name="1.1.5"
if [[ -z "$artifact_path" || ! -f "$artifact_path" ]]; then
  echo "Usage: tool/verify_android_release.sh <release.apk|release.aab>" >&2
  exit 2
fi

if ! java -version >/dev/null 2>&1 &&
  [[ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

case "$artifact_path" in
  *.apk)
    android_sdk_path="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
    if [[ -z "$android_sdk_path" && -f android/local.properties ]]; then
      android_sdk_path="$(sed -n 's/^sdk.dir=//p' android/local.properties | head -1)"
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
    ;;
  *.aab)
    # Upload keys are normally self-signed, so cryptographic verification must
    # not use jarsigner's -strict certificate-chain policy.
    if ! verification_output="$(jarsigner -verify -verbose -certs "$artifact_path" 2>&1)"; then
      echo "App bundle signature verification failed." >&2
      exit 1
    fi
    grep -qi 'jar verified' <<<"$verification_output"
    if grep -qi 'CN=Android Debug' <<<"$verification_output"; then
      echo "Refusing debug-signed release app bundle." >&2
      exit 1
    fi

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
    permissions="$(bundle_manifest_value '/manifest/uses-permission/@android:name')"
    debuggable="$(bundle_manifest_value '/manifest/application/@android:debuggable' 2>/dev/null || true)"
    ;;
  *)
    echo "Expected an .apk or .aab artifact." >&2
    exit 2
    ;;
esac

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

echo "Android release verified: $application_id $version_name ($version_code), target SDK $target_sdk, signed and non-debuggable."
