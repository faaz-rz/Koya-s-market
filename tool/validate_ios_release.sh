#!/usr/bin/env bash
set -euo pipefail

if [[ "${CONFIGURATION:-}" != "Release" ]]; then
  exit 0
fi

decode_base64() {
  if printf '%s' "$1" | /usr/bin/base64 --decode >/dev/null 2>&1; then
    printf '%s' "$1" | /usr/bin/base64 --decode
  else
    printf '%s' "$1" | /usr/bin/base64 -D
  fi
}

lowercase() {
  printf '%s' "$1" | /usr/bin/tr '[:upper:]' '[:lower:]'
}

is_placeholder() {
  case "$1" in
    *YOUR_*|*your_*|*example.com*|*example.invalid*) return 0 ;;
    *) return 1 ;;
  esac
}

supabase_url=""
supabase_anon_key=""
privacy_policy_url=""
account_deletion_url=""
review_login=""
push_notifications=""
razorpay_payments=""
firebase_project=""
firebase_sender=""
firebase_ios_key=""
firebase_ios_app=""

if [[ -n "${DART_DEFINES:-}" ]]; then
  IFS=',' read -r -a encoded_defines <<<"${DART_DEFINES}"
  for encoded_define in "${encoded_defines[@]}"; do
    [[ -n "$encoded_define" ]] || continue
    decoded_define="$(decode_base64 "$encoded_define")"
    case "$decoded_define" in
      SUPABASE_URL=*) supabase_url="${decoded_define#SUPABASE_URL=}" ;;
      SUPABASE_ANON_KEY=*) supabase_anon_key="${decoded_define#SUPABASE_ANON_KEY=}" ;;
      PRIVACY_POLICY_URL=*) privacy_policy_url="${decoded_define#PRIVACY_POLICY_URL=}" ;;
      ACCOUNT_DELETION_URL=*) account_deletion_url="${decoded_define#ACCOUNT_DELETION_URL=}" ;;
      ENABLE_PLAY_REVIEW_LOGIN=*) review_login="${decoded_define#ENABLE_PLAY_REVIEW_LOGIN=}" ;;
      ENABLE_PUSH_NOTIFICATIONS=*) push_notifications="${decoded_define#ENABLE_PUSH_NOTIFICATIONS=}" ;;
      ENABLE_RAZORPAY_PAYMENTS=*) razorpay_payments="${decoded_define#ENABLE_RAZORPAY_PAYMENTS=}" ;;
      FIREBASE_PROJECT_ID=*) firebase_project="${decoded_define#FIREBASE_PROJECT_ID=}" ;;
      FIREBASE_MESSAGING_SENDER_ID=*) firebase_sender="${decoded_define#FIREBASE_MESSAGING_SENDER_ID=}" ;;
      FIREBASE_IOS_API_KEY=*) firebase_ios_key="${decoded_define#FIREBASE_IOS_API_KEY=}" ;;
      FIREBASE_IOS_APP_ID=*) firebase_ios_app="${decoded_define#FIREBASE_IOS_APP_ID=}" ;;
    esac
  done
fi

missing=()
if [[ "$supabase_url" != https://* ]] || is_placeholder "$supabase_url"; then
  missing+=("SUPABASE_URL (production HTTPS URL)")
fi
if [[ -z "$supabase_anon_key" ]] || is_placeholder "$supabase_anon_key"; then
  missing+=("SUPABASE_ANON_KEY")
fi
if [[ "$privacy_policy_url" != https://* ]] || is_placeholder "$privacy_policy_url"; then
  missing+=("PRIVACY_POLICY_URL (production HTTPS URL)")
fi
if [[ "$account_deletion_url" != https://* ]] || is_placeholder "$account_deletion_url"; then
  missing+=("ACCOUNT_DELETION_URL (production HTTPS URL)")
fi
if [[ "$(lowercase "$review_login")" != "true" ]]; then
  missing+=("ENABLE_PLAY_REVIEW_LOGIN=true")
fi

if (( ${#missing[@]} > 0 )); then
  missing_list=""
  for missing_value in "${missing[@]}"; do
    if [[ -n "$missing_list" ]]; then
      missing_list="$missing_list, $missing_value"
    else
      missing_list="$missing_value"
    fi
  done
  printf 'error: Koya Stores iOS Release configuration is incomplete. Missing: %s.\n' "$missing_list" >&2
  printf 'error: Use the production flutter build ipa command documented in README.md. Use Profile mode for demo builds.\n' >&2
  exit 1
fi

if [[ "$(lowercase "$push_notifications")" == "true" ]]; then
  if [[ -z "$firebase_project" || -z "$firebase_sender" || -z "$firebase_ios_key" || -z "$firebase_ios_app" ]]; then
    printf 'error: Push configuration is incomplete. Supply the Firebase iOS public app configuration.\n' >&2
    exit 1
  fi
  entitlements_file="${SRCROOT:-$(pwd)/ios}/${CODE_SIGN_ENTITLEMENTS:-}"
  if [[ ! -f "$entitlements_file" ]] || [[ "$(/usr/libexec/PlistBuddy -c 'Print :aps-environment' "$entitlements_file" 2>/dev/null || true)" != "production" ]]; then
    printf 'error: Production push requires an APNs entitlement and matching Apple provisioning.\n' >&2
    exit 1
  fi
fi

if [[ "$(lowercase "$razorpay_payments")" == "true" ]]; then
  printf 'error: The first iOS release supports payment at handover only. The native online-payment SDK is intentionally excluded.\n' >&2
  exit 1
fi
