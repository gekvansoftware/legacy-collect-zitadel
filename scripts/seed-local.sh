#!/bin/sh
set -e

ZITADEL_HOST="${ZITADEL_DOMAIN:-localhost}"
ZITADEL_URL="http://zitadel-api:8080"
PAT_FILE="/zitadel/bootstrap/admin.pat"

echo "Waiting for Zitadel API to be ready..."
until curl -sf -H "Host: $ZITADEL_HOST" "$ZITADEL_URL/debug/ready" >/dev/null 2>&1; do
  sleep 2
done

echo "Waiting for PAT file..."
until [ -f "$PAT_FILE" ]; do
  sleep 2
done
sleep 3

PAT=$(cat "$PAT_FILE")

# Check if projects already exist
EXISTING=$(curl -sf -H "Host: $ZITADEL_HOST" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d '{"queries":[{"nameQuery":{"name":"LegacyCollect","method":"TEXT_QUERY_METHOD_EQUALS"}}]}' \
  "$ZITADEL_URL/management/v1/projects/_search" 2>/dev/null || echo '{}')

if echo "$EXISTING" | grep -q '"LegacyCollect"'; then
  echo "Project 'LegacyCollect' already exists. Skipping setup."
  exit 0
fi

echo "Creating project 'LegacyCollect'..."
PROJECT_RESPONSE=$(curl -sf -H "Host: $ZITADEL_HOST" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d '{"name":"LegacyCollect","projectRoleAssertion":true}' \
  "$ZITADEL_URL/management/v1/projects")

PROJECT_ID=$(echo "$PROJECT_RESPONSE" | jq -r '.id')
echo "Created project: $PROJECT_ID"

echo "Creating OIDC application 'LegacyCollect Web'..."
APP_RESPONSE=$(curl -sf -H "Host: $ZITADEL_HOST" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"LegacyCollect Web\",
    \"redirectUris\": [\"http://localhost:5173/callback\"],
    \"postLogoutRedirectUris\": [\"http://localhost:5173\"],
    \"responseTypes\": [\"OIDC_RESPONSE_TYPE_CODE\"],
    \"grantTypes\": [\"OIDC_GRANT_TYPE_AUTHORIZATION_CODE\"],
    \"appType\": \"OIDC_APP_TYPE_USER_AGENT\",
    \"authMethodType\": \"OIDC_AUTH_METHOD_TYPE_NONE\",
    \"devMode\": true,
    \"accessTokenType\": \"OIDC_TOKEN_TYPE_JWT\",
    \"accessTokenRoleAssertion\": true,
    \"idTokenRoleAssertion\": true
  }" \
  "$ZITADEL_URL/management/v1/projects/$PROJECT_ID/apps/oidc")

CLIENT_ID=$(echo "$APP_RESPONSE" | jq -r '.clientId')
echo "Created OIDC app with client_id: $CLIENT_ID"

echo "$CLIENT_ID" > /zitadel/bootstrap/client_id

echo "Configuring login policy (disable passkey, register, IDP)..."
curl -sf -X PUT -H "Host: $ZITADEL_HOST" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "allowUsernamePassword": true,
    "allowRegister": false,
    "allowExternalIdp": false,
    "forceMfa": false,
    "passwordlessType": "PASSWORDLESS_TYPE_NOT_ALLOWED",
    "hidePasswordReset": false,
    "forceMfaLocalOnly": false,
    "allowDomainDiscovery": false,
    "ignoreUnknownUsernames": false,
    "disableLoginWithEmail": false,
    "disableLoginWithPhone": true
  }' \
  "$ZITADEL_URL/admin/v1/policies/login" >/dev/null

echo "Login policy configured."

echo "Renaming default organization to 'Legacy'..."
curl -sf -X PUT -H "Host: $ZITADEL_HOST" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d '{"name":"Legacy"}' \
  "$ZITADEL_URL/management/v1/orgs/me" >/dev/null

echo "Default organization renamed to 'Legacy'."

#################################################################
# Configure SMTP (route all outgoing mail to the local Mailpit)
#################################################################

echo "Configuring SMTP provider (Mailpit)..."
SMTP_RESPONSE=$(curl -sf -H "Host: $ZITADEL_HOST" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "senderAddress": "noreply@localhost",
    "senderName": "Legacy Collect",
    "replyToAddress": "",
    "tls": false,
    "host": "mailpit-auth:1025",
    "none": {}
  }' \
  "$ZITADEL_URL/admin/v1/email/smtp")

SMTP_ID=$(echo "$SMTP_RESPONSE" | jq -r '.id')

if [ -n "$SMTP_ID" ] && [ "$SMTP_ID" != "null" ]; then
  echo "SMTP provider created: $SMTP_ID"
  echo "Activating SMTP provider..."
  curl -sf -X POST -H "Host: $ZITADEL_HOST" \
    -H "Authorization: Bearer $PAT" \
    -H "Content-Type: application/json" \
    "$ZITADEL_URL/admin/v1/email/$SMTP_ID/_activate" >/dev/null
  echo "SMTP provider activated. Mail routes to Mailpit (http://localhost:8026)."
else
  echo "WARN: could not create SMTP provider (one may already exist). Response: $SMTP_RESPONSE"
fi

#################################################################
# Create test user
#################################################################

echo "Creating test user..."
USER_RESPONSE=$(curl -sf -H "Host: $ZITADEL_HOST" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test@most.dev",
    "profile": {
      "givenName": "Test",
      "familyName": "User",
      "displayName": "Test User"
    },
    "email": {
      "email": "test@most.dev",
      "isVerified": true
    },
    "password": {
      "password": "MostDev1234!",
      "changeRequired": true
    }
  }' \
  "$ZITADEL_URL/v2/users/human")

USER_ID=$(echo "$USER_RESPONSE" | jq -r '.userId')
echo "Test user created: test@most.dev / MostDev1234! (password change required)"

echo ""
echo "=== Zitadel Setup Complete ==="
echo "OIDC Client ID (LegacyCollect Web): $CLIENT_ID"
echo "Issuer: http://localhost:${ZITADEL_EXTERNALPORT:-8080}"
echo ""
echo "Set in your frontend .env:"
echo "  VITE_ZITADEL_CLIENT_ID=$CLIENT_ID"
echo "=============================="
