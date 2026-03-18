
#!/bin/bash
echo "[Keycloak] Starting configuration"

_KCADM="/opt/keycloak/keycloak-26.2.4/bin/kcadm.sh"
KEYCLOAK_URL="https://keycloak.main.system:9080"
KEYCLOAK_ADMIN="admin"
KEYCLOAK_ADMIN_PASSWORD="changeme"
REALM="system"
CLIENT_URL="https://nextcloud.main.system"
CLIENT_ID="nextcloud"
KEYCLOAK_GROUPS=("nc-admin" "nc-analyst" "nc-commander")

$_KCADM config credentials \
  --server $KEYCLOAK_URL \
  --realm master \
  --user $KEYCLOAK_ADMIN \
  --password $KEYCLOAK_ADMIN_PASSWORD

$_KCADM create groups -r $REALM -s name=nextcloud

for g in "${KEYCLOAK_GROUPS[@]}"; do
  $_KCADM create groups/$($_KCADM get groups -r $REALM --fields id,name | jq -r '.[] | select(.name=="nextcloud") | .id')/children -r $REALM -s name=$g
done

cat > /tmp/${CLIENT_ID}-saml.json <<EOF
{
  "clientId": "${CLIENT_ID}",
  "name": "Nextcloud SAML Client",
  "enabled": true,
  "protocol": "saml",
  "frontchannelLogout": true,
  "attributes": {
    "saml.authnstatement": "true",
    "saml.server.signature": "true",
    "saml.assertion.signature": "true",
    "saml.signature.algorithm": "RSA_SHA256",
    "saml.client.signature": "false",
    "saml.encrypt": "false",
    "saml_force_name_id_format": "true",
    "saml_name_id_format": "email",
    "saml_assertion_consumer_url_post": "${CLIENT_URL}/apps/user_saml/saml/acs",
    "saml_assertion_consumer_url_redirect": "${CLIENT_URL}/apps/user_saml/saml/acs"
  },
  "redirectUris": ["${CLIENT_URL}/*"],
  "baseUrl": "${CLIENT_URL}",
  "adminUrl": "${CLIENT_URL}/apps/user_saml/saml/acs",
  "protocolMappers": [
    {
      "name": "displayName",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "consentRequired": false,
      "config": {
        "attribute.nameformat": "Basic",
        "user.attribute": "username",
        "attribute.name": "displayName"
      }
    },
    {
      "name": "email",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "config": {
        "user.attribute": "email",
        "attribute.name": "email"
      }
    },
    {
      "name": "groups",
      "protocol": "saml",
      "protocolMapper": "saml-group-membership-mapper",
      "config": {
        "full.path": "false",
        "single": "true",
        "attribute.name": "role",
        "filter": "true",
        "groups": "/nextcloud"
      }
    }
  ]
}
EOF

# --- Create or update client ---
if $_KCADM get clients -r $REALM | jq -e ".[] | select(.clientId==\"$CLIENT_ID\")" > /dev/null; then
  echo "[Keycloak] Updating existing client"
  CLIENT_UUID=$($_KCADM get clients -r $REALM | jq -r ".[] | select(.clientId==\"$CLIENT_ID\") | .id")
  $_KCADM update clients/$CLIENT_UUID -r $REALM -f /tmp/${CLIENT_ID}-saml.json
else
  echo "[Keycloak] Creating client"
  $_KCADM create clients -r $REALM -f /tmp/${CLIENT_ID}-saml.json
fi

echo "[Keycloak] Configuration complete"









#!/bin/bash

KCADM="/opt/keycloak/keycloak-26.2.4/bin/kcadm.sh"
KEYCLOAK_URL="https://keycloak.main.system:9080"
KEYCLOAK_ADMIN="admin"
KEYCLOAK_ADMIN_PASSWORD="changeme"
REALM="system"
CLIENT_ID="nextcloud"

# --- Authenticate ---
$KCADM config credentials --server $KEYCLOAK_URL --realm master --user $KEYCLOAK_ADMIN --password $KEYCLOAK_ADMIN_PASSWORD
echo "[Keycloak] Authenticated"

# --- Create or get client ---
CLIENT_UUID=$($KCADM get clients -r $REALM | jq -r ".[] | select(.clientId==\"$CLIENT_ID\") | .id // empty")
if [ -z "$CLIENT_UUID" ]; then
    $KCADM create clients -r $REALM -s clientId=$CLIENT_ID -s name="Nextcloud SAML" -s enabled=true -s protocol="saml"
    CLIENT_UUID=$($KCADM get clients -r $REALM | jq -r ".[] | select(.clientId==\"$CLIENT_ID\") | .id")
    echo "[Keycloak] Created SAML client: $CLIENT_ID"
else
    echo "[Keycloak] Using existing SAML client: $CLIENT_ID"
fi

# --- Create client scope for filtered roles ---
CLIENT_SCOPE_NAME="nextcloud-roles"
SCOPE_UUID=$($KCADM get client-scopes -r $REALM | jq -r ".[] | select(.name==\"$CLIENT_SCOPE_NAME\") | .id // empty")
if [ -z "$SCOPE_UUID" ]; then
    $KCADM create client-scopes -r $REALM -s name="$CLIENT_SCOPE_NAME" -s protocol="saml"
    SCOPE_UUID=$($KCADM get client-scopes -r $REALM | jq -r ".[] | select(.name==\"$CLIENT_SCOPE_NAME\") | .id")
    echo "[Keycloak] Created client scope: $CLIENT_SCOPE_NAME"
else
    echo "[Keycloak] Using existing client scope: $CLIENT_SCOPE_NAME"
fi

# --- Add Role List Mapper to the client scope ---
MAPPER_NAME="nextcloud-role-mapper"
EXISTS=$($KCADM get client-scopes/$SCOPE_UUID/protocol-mappers/models -r $REALM | jq -r ".[] | select(.name==\"$MAPPER_NAME\") | .id // empty")
if [ -z "$EXISTS" ]; then
    $KCADM create client-scopes/$SCOPE_UUID/protocol-mappers/models -r $REALM -s name="$MAPPER_NAME" \
        -s protocol="saml" \
        -s protocolMapper="saml-role-list-mapper" \
        -s 'consentRequired=false' \
        -s 'config.single=true' \
        -s 'config.attribute.name=role' \
        -s 'config.attribute.nameformat=Basic' \
        -s 'config.role=nc-admin,nc-analyst,nc-commander'
    echo "[Keycloak] Added filtered role mapper to client scope"
else
    echo "[Keycloak] Role mapper already exists in client scope"
fi

# --- Assign client scope to client (default) ---
ASSIGNED=$($KCADM get clients/$CLIENT_UUID/default-client-scopes -r $REALM | jq -r ".[] | select(.id==\"$SCOPE_UUID\") | .id // empty")
if [ -z "$ASSIGNED" ]; then
    $KCADM add clients/$CLIENT_UUID/default-client-scopes/$SCOPE_UUID -r $REALM
    echo "[Keycloak] Assigned client scope to SAML client"
else
    echo "[Keycloak] Client scope already assigned to client"
fi

echo "[Keycloak] Nextcloud SAML client setup complete. Only nc-* roles will be sent in SAML assertion."