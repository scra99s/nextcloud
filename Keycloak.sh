echo "[App_Config] Configure application (user_saml)"
php /var/www/html/occ config:app:set user_saml general-require_provisioned_account --value="0"
php /var/www/html/occ config:app:set user_saml general-allow_multiple_user_back_ends --value="1"
php /var/www/html/occ config:app:set user_saml type --value='saml'
php /var/www/html/occ config:app:set user_saml saml_use_group_prefix --value=0
php /var/www/html/occ config:app:set user_saml use_group_mapping --value=1
php /var/www/html/occ config:app:set user_saml saml_admin_group --value="nc-admin"

samlProfile=$(php /var/www/html/occ saml:config:create)
php /var/www/html/occ saml:config:set ${samlProfile} \
  --general-idp0_display_name "Sign in with Keycloak" \
  --general-is_saml_request_using_post "0" \
  --general-uid_mapping "email" \
  --sp-entityId "nextcloud" \
  --sp-name-id-format "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified" \
  --security-authnRequestsSigned "0" \
  --security-signMetadata "0" \
  --security-wantAssertionsEncrypted "0" \
  --security-wantAssertionsSigned "0" \
  --security-wantMessagesSigned "0" \
  --saml-attribute-mapping-displayName_mapping "email" \
  --saml-attribute-mapping-email_mapping "email" \
  --saml-attribute-mapping-group_mapping "role" \
  --saml-user-filter-require_groups "nc-admin, nc-commander, nc-analyst" \
  --idp-singleSignOnService.url "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/saml" \
  --idp-singleLogoutService.url "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/saml" \
  --idp-entityId "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}" \
  --idp-x509cert """
$(cat /opt/apps/keycloak.pem)
"""

#################################################################


KCADM="/opt/keycloak/keycloak-26.2.4/bin/kcadm.sh"
KEYCLOAK_LOCAL_URL="https://keycloak.main.system:9080"
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=changeme
REALM=system

# Auth to Keycloak default master realm
${KCADM} config credentials --server ${KEYCLOAK_LOCAL_URL} --realm master --user ${KEYCLOAK_ADMIN} --password ${KEYCLOAK_ADMIN_PASSWORD}

${KCADM} create groups -r $REALM -s name=nextcloud
${KCADM} create groups/$(${KCADM} get groups -r $REALM --fields id,name | jq -r '.[] | select(.name=="nextcloud") | .id')/children -r $REALM -s name=nc-admin
${KCADM} create groups/$(${KCADM} get groups -r $REALM --fields id,name | jq -r '.[] | select(.name=="nextcloud") | .id')/children -r $REALM -s name=nc-analyst
${KCADM} create groups/$(${KCADM} get groups -r $REALM --fields id,name | jq -r '.[] | select(.name=="nextcloud") | .id')/children -r $REALM -s name=nc-commander

function createclient() {
  KEYCLOAK_CLIENT_NAME=$1
  KEYCLOAK_ROLES_MAPPER_SINGLE=$2

  cat > /tmp/${KEYCLOAK_CLIENT_NAME}-saml-client.json <<EOF
{
  "clientId": "${KEYCLOAK_CLIENT_NAME}",
  "name": "${KEYCLOAK_CLIENT_NAME} Client",
  "enabled": true,
  "protocol": "saml",
  "frontchannelLogout": true,
  "attributes": {
    "saml.authnstatement": "true",
    "saml.server.signature": "true",
    "saml.signature.algorithm": "RSA_SHA256",
    "saml.client.signature": "false",
    "saml.assertion.signature": "true",
    "saml_assertion_consumer_url_post": "https://${KEYCLOAK_CLIENT_NAME}.main.system/saml/acs",
    "saml_assertion_consumer_url_redirect": "https://${KEYCLOAK_CLIENT_NAME}.main.system/saml/acs",
    "saml.encrypt": "false",
    "saml_force_name_id_format": "true",
    "saml_name_id_format": "username",
    "saml.signing.certificate": "",
    "saml.signing.private.key": ""
  },
  "redirectUris": ["https://${KEYCLOAK_CLIENT_NAME}.main.system/*"],
  "baseUrl": "https://${KEYCLOAK_CLIENT_NAME}.main.system",
  "rootUrl": "https://${KEYCLOAK_CLIENT_NAME}.main.system",
  "adminUrl": "https://${KEYCLOAK_CLIENT_NAME}.main.system/saml/acs",
  "fullScopeAllowed": false,
  "defaultClientScopes": ["saml_organization"],
  "protocolMappers": [
    {
      "name": "username",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "consentRequired": false,
      "config": {
        "attribute.nameformat": "Basic",
        "user.attribute": "username",
        "attribute.name": "username"
      }
    },
    {
      "name": "email",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "consentRequired": false,
      "config": {
        "attribute.nameformat": "Basic",
        "user.attribute": "email",
        "attribute.name": "email"
      }
    },
    {
      "name": "firstName",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "consentRequired": false,
      "config": {
        "attribute.nameformat": "Basic",
        "user.attribute": "firstName",
        "attribute.name": "firstName"
      }
    },
    {
      "name": "lastName",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "consentRequired": false,
      "config": {
        "attribute.nameformat": "Basic",
        "user.attribute": "lastName",
        "attribute.name": "lastName"
      }
    },
    {
      "name": "role list",
      "protocol": "saml",
      "protocolMapper": "saml-role-list-mapper",
      "consentRequired": false,
      "config": {
        "single": "${KEYCLOAK_ROLES_MAPPER_SINGLE}",
        "attribute.nameformat": "Basic",
        "attribute.name": "role"
      }
    },
    {
      "name": "nextcloud-groups",
      "protocol": "saml",
      "protocolMapper": "saml-group-membership-mapper",
      "consentRequired": false,
      "config": {
        "attribute.name": "groups",
        "full.path": "false",
        "single": "true",
        "group.filter": "/nextcloud"
      }
    }
  ]
}

############################

#!/bin/bash

KCADM="/opt/keycloak/keycloak-26.2.4/bin/kcadm.sh"
KEYCLOAK_LOCAL_URL="https://keycloak.main.system:9080"
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=changeme
LDAP_BIND_PASSWORD="changeme"

# Auth to Keycloak
${KCADM} config credentials --server ${KEYCLOAK_LOCAL_URL} --realm master --user ${KEYCLOAK_ADMIN} --password ${KEYCLOAK_ADMIN_PASSWORD}

# Create Realm
${KCADM} create realms -s realm=system -s enabled=true -s displayName="System SSO Realm"

# Create LDAP Binding
${KCADM} create components -r system -s name=ldap-freeipa -s providerId=ldap -s providerType=org.keycloak.storage.UserStorageProvider \
  -s 'config.priority=["1"]' \
  -s 'config.enabled=["true"]' \
  -s 'config.cachePolicy=["DEFAULT"]' \
  -s 'config.evictionDay=[""]' \
  -s 'config.evictionHour=[""]' \
  -s 'config.evictionMinute=[""]' \
  -s 'config.maxLifespan=[""]' \
  -s 'config.batchSizeForSync=["1000"]' \
  -s 'config.editMode=["READ_ONLY"]' \
  -s 'config.syncRegistrations=["true"]' \
  -s 'config.fullSyncPeriod=["3600"]' \
  -s 'config.changedSyncPeriod=["300"]' \
  -s 'config.vendor=["other"]' \
  -s 'config.usernameLDAPAttribute=["uid"]' \
  -s 'config.rdnLDAPAttribute=["uid"]' \
  -s 'config.uuidLDAPAttribute=["uid"]' \
  -s 'config.userObjectClasses=["inetOrgPerson, organizationalPerson"]' \
  -s "config.connectionUrl=[\"ldap://localhost:389\"]" \
  -s "config.usersDn=[\"cn=users,cn=accounts,dc=main,dc=system\"]" \
  -s "config.authType=[\"simple\"]" \
  -s "config.bindDn=[\"uid=svc-bind,cn=users,cn=accounts,dc=main,dc=system\"]" \
  -s "config.bindCredential=[\"${LDAP_BIND_PASSWORD}\"]" \
  -s 'config.trustEmail=["true"]' \
  -s 'config.searchScope=["2"]' \
  -s 'config.useTruststoreSpi=["ldapsOnly"]' \
  -s 'config.connectionPooling=["true"]' \
  -s 'config.pagination=["true"]' \
  -s 'config.allowKerberosAuthentication=["false"]' \
  -s 'config.debug=["false"]' \
  -s 'config.useKerberosForPasswordAuthentication=["true"]'

# Get LDAP ID
LDAP_ID=$(${KCADM} get components -r system --fields id,name | grep -B1 "freeipa" | grep "id" | cut -d'"' -f4)

# Create User Mapping
${KCADM} create components -r system \
  -s name=group-ldap-mapper \
  -s providerId=group-ldap-mapper \
  -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
  -s parentId=${LDAP_ID} \
  -s 'config."groups.dn"=["cn=groups,cn=accounts,dc=main,dc=system"]' \
  -s 'config."group.name.ldap.attribute"=["cn"]' \
  -s 'config."group.object.classes"=["groupOfNames"]' \
  -s 'config."preserve.group.inheritance"=["true"]' \
  -s 'config."membership.ldap.attribute"=["member"]' \
  -s 'config."membership.attribute.type"=["DN"]' \
  -s 'config."groups.ldap.filter"=[]' \
  -s 'config.mode=["LDAP_ONLY"]' \
  -s 'config."user.roles.retrieve.strategy"=["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"]' \
  -s 'config."mapped.group.attributes"=[""]' \
  -s 'config."drop.non.existing.groups.during.sync"=["false"]'

# Create Role Mapping
${KCADM} create components -r system \
  -s name=role-ldap-mapper \
  -s providerId=role-ldap-mapper \
  -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
  -s parentId=${LDAP_ID} \
  -s 'config."roles.dn"=["cn=groups,cn=accounts,dc=main,dc=system"]' \
  -s 'config."role.name.ldap.attribute"=["cn"]' \
  -s 'config."role.object.classes"=["groupOfNames"]' \
  -s 'config."membership.ldap.attribute"=["member"]' \
  -s 'config."membership.attribute.type"=["DN"]' \
  -s 'config."roles.ldap.filter"=[]' \
  -s 'config.mode=["LDAP_ONLY"]' \
  -s 'config."user.roles.retrieve.strategy"=["LOAD_ROLES_BY_MEMBER_ATTRIBUTE"]' \
  -s 'config."use.realm.roles.mapping"=["true"]'

# Sync Users into Keycloak
${KCADM} create user-storage/${LDAP_ID}/sync?action=triggerFullSync -r system
