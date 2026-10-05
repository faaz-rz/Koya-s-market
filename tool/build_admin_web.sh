#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Admin web build failed: %s\n' "$1" >&2
  exit 1
}

require_value() {
  local variable_name="$1"
  local variable_value="${!variable_name:-}"
  [[ -n "$variable_value" ]] || fail "$variable_name is required."
}

require_https_url() {
  local variable_name="$1"
  local variable_value="${!variable_name:-}"
  [[ "$variable_value" == https://* ]] || fail "$variable_name must be an HTTPS URL."
}

require_value SUPABASE_URL
require_value SUPABASE_ANON_KEY
require_https_url SUPABASE_URL
# When omitted, the web app uses the privacy/deletion pages bundled at the
# deployed HTTPS origin. Native release builds still require explicit URLs.
[[ -z "${PRIVACY_POLICY_URL:-}" ]] || require_https_url PRIVACY_POLICY_URL
[[ -z "${ACCOUNT_DELETION_URL:-}" ]] || require_https_url ACCOUNT_DELETION_URL

case "$SUPABASE_ANON_KEY" in
  sb_secret_*|*service_role*)
    fail 'SUPABASE_ANON_KEY must be the public publishable/anon key, never a secret or service-role key.'
    ;;
esac

readonly koyas_flutter_version='3.47.1'
koyas_flutter_bin="$(command -v flutter || true)"

if [[ -z "$koyas_flutter_bin" ]]; then
  koyas_flutter_root="${TMPDIR:-/tmp}/koyas-flutter-${koyas_flutter_version}"
  if [[ ! -x "$koyas_flutter_root/bin/flutter" ]]; then
    git clone --depth 1 --branch "$koyas_flutter_version" \
      https://github.com/flutter/flutter.git "$koyas_flutter_root"
  fi
  koyas_flutter_bin="$koyas_flutter_root/bin/flutter"
fi

"$koyas_flutter_bin" config --no-analytics >/dev/null
"$koyas_flutter_bin" pub get
"$koyas_flutter_bin" build web \
  --release \
  -t lib/admin_main.dart \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY" \
  --dart-define="PRIVACY_POLICY_URL=${PRIVACY_POLICY_URL:-}" \
  --dart-define="ACCOUNT_DELETION_URL=${ACCOUNT_DELETION_URL:-}" \
  --dart-define="ADMIN_IDLE_TIMEOUT_MINUTES=${ADMIN_IDLE_TIMEOUT_MINUTES:-15}"

# Old local/cached Flutter bundles may retain the removed wildcard rewrite.
# Cloudflare handles SPA navigation natively; the rewrite loops on index.html.
rm -f build/web/_redirects
