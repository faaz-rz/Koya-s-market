#!/usr/bin/env bash
set -euo pipefail

# Workers Builds can run the deploy command without a separate build step.
# Always compile this checkout before asking Wrangler to upload its assets.
koyas_repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$koyas_repo_root"

bash tool/build_admin_web.sh
exec npx --yes wrangler@4.147.0 deploy "$@"
