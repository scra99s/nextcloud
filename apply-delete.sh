#!/bin/bash

declare nextcloudDefinitions=(
  Namespace.yaml Certificates.yaml ServiceAccount.yaml Service.yaml
  ConfigMap.yaml Secret.yaml PersistentVolumeClaim.yaml
  PodDisruptionBudget.yaml NetworkPolicy.yaml StatefulSet.yaml
  Deployment.yaml Ingress.yaml
)

declare KeycloakDefinitions=(
  Namespace.yaml Certificates.yaml ServiceAccount.yaml Service.yaml
  ConfigMap.yaml Secret.yaml PodDisruptionBudget.yaml NetworkPolicy.yaml
  StatefulSet.yaml Deployment.yaml Ingress.yaml
)

nextcloud() {
  for file in "${nextcloudDefinitions[@]}"; do
    kubectl $1 -f nextcloud-definitions/$file
  done
}

keycloak() {
  for file in "${KeycloakDefinitions[@]}"; do
    kubectl $1 -f keycloak-definitions/$file
  done
}

case "$1" in
  nextcloud) nextcloud $2;;
  keycloak) keycloak $2;;
esac
