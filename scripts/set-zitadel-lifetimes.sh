#!/bin/bash
# Set the instance OIDC token lifetimes: access/id token 15 min, refresh idle 30 min
# (ends an inactive portal session, since the portal renews with refresh tokens),
# refresh max 8 h (hard cap). Idempotent; safe to rerun.
#
# Usage:
#   ZITADEL_PAT=<instance PAT with iam.write> ./scripts/set-zitadel-lifetimes.sh <base-url>
#
#   ./scripts/set-zitadel-lifetimes.sh                                   # local compose stack
#   ZITADEL_PAT=xxx ./scripts/set-zitadel-lifetimes.sh https://test-auth.powerq.dev
#
# Manual alternative (Zitadel Console, per environment):
#   1. Log in as an instance admin: https://<auth-domain>/ui/console
#   2. Default Settings (instance level, not an organisation) -> Lifetime and Expiration
#   3. Access Token Lifetime 15 min, ID Token Lifetime 15 min,
#      Refresh Token Idle Expiration 30 min, Refresh Token Expiration 8 h
#   4. Save. New tokens pick it up immediately; running sessions renew into it.
#   The Console form takes hours (15 min = 0.25, 30 min = 0.5); if it refuses
#   fractions, use this script — the API takes seconds.
set -euo pipefail

BASE_URL="${1:-http://localhost:8080/api}"
PAT="${ZITADEL_PAT:-}"

if [ -z "$PAT" ] && [ "$BASE_URL" = "http://localhost:8080/api" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$(dirname "$SCRIPT_DIR")"
  PAT=$(docker compose exec -T login-app cat /zitadel/bootstrap/admin.pat 2>/dev/null || true)
fi

if [ -z "$PAT" ]; then
  echo "No PAT. Pass it as ZITADEL_PAT=... (instance PAT with iam.write)." >&2
  exit 1
fi

echo -n "Setting OIDC token lifetimes on $BASE_URL (15m/15m, idle 30m, max 8h)..."
RESULT=$(curl -s -X PUT "$BASE_URL/admin/v1/settings/oidc" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "accessTokenLifetime": "900s",
    "idTokenLifetime": "900s",
    "refreshTokenIdleExpiration": "1800s",
    "refreshTokenExpiration": "28800s"
  }')

if echo "$RESULT" | grep -qi "details\|no changes"; then
  echo " done"
else
  echo " failed: $RESULT" >&2
  exit 1
fi

echo "Current settings:"
curl -s "$BASE_URL/admin/v1/settings/oidc" -H "Authorization: Bearer $PAT" | python3 -m json.tool
