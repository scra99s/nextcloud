KEYCLOAK_URL="https://keycloak.example.com/auth"
REALM="your_realm_name"
ADMIN_USER="admin"
ADMIN_PASS="admin_password"
SAML_CLIENT_ID="nextcloud"
NEXTCLOUD_PUBLIC_URL="https://nextcloud.example.com"

# === 1. Get access token ===
TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$ADMIN_USER" \
  -d "password=$ADMIN_PASS" \
  -d 'grant_type=password' \
  -d 'client_id=admin-cli' | jq -r '.access_token')

if [ -z "$TOKEN" ]; then
  echo "Failed to get access token!"
  exit 1
fi

# === 2. Create group hierarchy ===
GROUP_JSON=$(cat <<EOF
{
  "name": "nextcloud",
  "children": [
    { "name": "nc-admin" },
    { "name": "nc-analyst" },
    { "name": "nc-commander" }
  ]
}
EOF
)

curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/groups" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$GROUP_JSON"

echo "Created group hierarchy under /nextcloud"

# === 3. Create the SAML client ===
CLIENT_JSON=$(cat <<EOF
{
    "clientId": "$SAML_CLIENT_ID",
    "name": "Nextcloud",
    "description": "Nextcloud SAML Service Provider",
    "protocol": "saml",
    "enabled": true,
    "rootUrl": "$NEXTCLOUD_PUBLIC_URL",
    "baseUrl": "$NEXTCLOUD_PUBLIC_URL",
    "redirectUris": ["$NEXTCLOUD_PUBLIC_URL/*"],
    "adminUrl": "$NEXTCLOUD_PUBLIC_URL/apps/user_saml/saml/acs",
    "attributes": {
        "saml.authnstatement": "true",
        "saml.server.signature": "true",
        "saml.assertion.signature": "true",
        "saml.force.post.binding": "true",
        "saml.client.signature": "false",
        "saml_name_id_format": "username",
        "saml_single_logout_service_url_post": "$NEXTCLOUD_PUBLIC_URL/apps/user_saml/saml/sls",
        "saml_assertion_consumer_url_post": "$NEXTCLOUD_PUBLIC_URL/apps/user_saml/saml/acs",
        "saml_single_logout_service_url_redirect": "$NEXTCLOUD_PUBLIC_URL/apps/user_saml/saml/sls"
    },
    "fullScopeAllowed": false,
    "frontchannelLogout": true
}
EOF
)

curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$CLIENT_JSON"

echo "Created SAML client $SAML_CLIENT_ID"

# === 4. Get the client UUID ===
CLIENT_UUID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/clients?clientId=$SAML_CLIENT_ID" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.[0].id')

# === 5. Add group membership mapper with hierarchy filter ===
MAPPER_JSON=$(cat <<EOF
{
  "name": "nextcloud-groups",
  "protocol": "saml",
  "protocolMapper": "saml-group-membership-mapper",
  "consentRequired": false,
  "config": {
    "attribute.name": "groups",
    "full.path": "false",
    "single": "false",
    "group.filter": "/nextcloud"
  }
}
EOF
)

curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLIENT_UUID/protocol-mappers/models" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$MAPPER_JSON"

echo "Added group membership mapper with hierarchy filter for /nextcloud"

# kcadm.sh create groups -r $REALM -s name=nextcloud
# kcadm.sh create groups/$(kcadm.sh get groups -r $REALM --fields id,name | jq -r '.[] | select(.name=="nextcloud") | .id')/children -r $REALM -s name=nc-admin
# kcadm.sh create groups/$(kcadm.sh get groups -r $REALM --fields id,name | jq -r '.[] | select(.name=="nextcloud") | .id')/children -r $REALM -s name=nc-analyst
# kcadm.sh create groups/$(kcadm.sh get groups -r $REALM --fields id,name | jq -r '.[] | select(.name=="nextcloud") | .id')/children -r $REALM -s name=nc-commander

# Nextcloud
## Remove the group prefix "SAML_" from the keycloak saml group
php occ config:app:set user_saml saml_use_group_prefix --value=0

## Set the group provisioning as the groups already exist in nextcloud
php occ config:app:set user_saml use_group_mapping --value=1

# Assign Nextcloud admin role to nc-admin group
sudo -u www-data php occ config:app:set user_saml saml_admin_group --value="nc-admin"