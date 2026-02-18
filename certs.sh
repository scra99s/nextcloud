#!/bin/bash

set -e

# Configuration
ROOT_CA_KEY="rootCA.key"
ROOT_CA_CERT="rootCA.crt"
SERVER_KEY="server.key"
SERVER_CSR="server.csr"
SERVER_CERT="server.crt"
DAYS_VALID=825

DOMAIN="*.main.system"

echo "==> Generating Root CA private key"
openssl genrsa -out ${ROOT_CA_KEY} 4096

echo "==> Generating Root CA certificate"
openssl req -x509 -new -nodes \
  -key ${ROOT_CA_KEY} \
  -sha256 -days 3650 \
  -out ${ROOT_CA_CERT} \
  -subj "/C=US/ST=State/L=City/O=MainSystem/OU=IT/CN=MainSystem Root CA"

echo "==> Generating Server private key"
openssl genrsa -out ${SERVER_KEY} 2048

echo "==> Creating OpenSSL config for SAN"
cat > san.cnf <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C=US
ST=State
L=City
O=MainSystem
OU=IT
CN=main.system

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = collabora.main.system
DNS.2 = nextcloud.main.system
DNS.3 = *.main.system
EOF

echo "==> Generating CSR with SAN"
openssl req -new -key ${SERVER_KEY} \
  -out ${SERVER_CSR} \
  -config san.cnf

echo "==> Signing server certificate with Root CA"
openssl x509 -req \
  -in ${SERVER_CSR} \
  -CA ${ROOT_CA_CERT} \
  -CAkey ${ROOT_CA_KEY} \
  -CAcreateserial \
  -out ${SERVER_CERT} \
  -days ${DAYS_VALID} \
  -sha256 \
  -extensions req_ext \
  -extfile san.cnf

echo "==> Cleaning up"
rm san.cnf ${SERVER_CSR}

echo ""
echo "Done!"
echo "Root CA:      ${ROOT_CA_CERT}"
echo "Server Cert:  ${SERVER_CERT}"
echo "Server Key:   ${SERVER_KEY}"
