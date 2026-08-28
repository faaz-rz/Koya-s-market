#!/usr/bin/env bash
set -euo pipefail

artifact_path="${1:-}"
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
    ;;
  *.aab)
    if ! verification_output="$(jarsigner -verify -strict -certs "$artifact_path" 2>&1)"; then
      echo "App bundle signature verification failed." >&2
      exit 1
    fi
    grep -qi 'jar verified' <<<"$verification_output"
    if grep -qi 'CN=Android Debug' <<<"$verification_output"; then
      echo "Refusing debug-signed release app bundle." >&2
      exit 1
    fi
    ;;
  *)
    echo "Expected an .apk or .aab artifact." >&2
    exit 2
    ;;
esac

echo "Android release signature verified: $artifact_path"
