_OCC="php /var/www/html/occ"

# $_OCC db:add-missing-indices
# $_OCC maintenance:repair --include-expensive

function configure_saml() {
  local samlProfile=""
  local idpCert=""

  $_OCC app:enable user_saml
  $_OCC config:app:set user_saml general-require_provisioned_account --value="0"
  $_OCC config:app:set user_saml general-allow_multiple_user_back_ends --value="1"
  $_OCC config:app:set user_saml type --value="saml"
  $_OCC config:app:set user_saml saml_use_group_prefix --value="0"
  $_OCC config:app:set user_saml use_group_mapping --value="1"
  $_OCC config:app:set user_saml saml_admin_group --value="nc-admin"

  idpCert=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' ${KEYCLOAK_CERT_PATH})

  samlProfile=$($_OCC saml:config:create)
  $_OCC saml:config:set ${samlProfile} \
    --general-idp0_display_name "Sign in with Keycloak" \
    --general-is_saml_request_using_post "0" \
    --general-uid_mapping "email" \
    --sp-entityId "nextcloud" \
    --sp-name-id-format "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress" \
    --security-authnRequestsSigned "1" \
    --security-signMetadata "1" \
    --security-wantAssertionsEncrypted "0" \
    --security-wantAssertionsSigned "1" \
    --security-wantMessagesSigned "1" \
    --saml-attribute-mapping-displayName_mapping "displayName" \
    --saml-attribute-mapping-email_mapping "email" \
    --saml-attribute-mapping-group_mapping "role" \
    --saml-user-filter-require_groups "nc-admin,nc-commander,nc-analyst" \
    --idp-singleSignOnService.url "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/saml" \
    --idp-singleLogoutService.url "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/saml" \
    --idp-entityId "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}" \
    --idp-x509cert "$idpCert"

  touch /var/www/html/saml_configured
}

if [[ -f /var/www/html/saml_configured ]]; then
  echo "SAML already configured, skipping"
  exit 0
else
  # Check if Keycloak certificate exists and is valid before proceeding with SAML configuration.
  if ! openssl x509 -in "${KEYCLOAK_CERT_PATH}" -noout >/dev/null 2>&1; then
    echo "Keycloak certificate not found at ${KEYCLOAK_CERT_PATH} or certificate is invalid, skipping SAML configuration"
    exit 0
  fi
  configure_saml
fi
                  