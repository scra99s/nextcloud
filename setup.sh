#!/bin/bash

declare definitions=(
  Namespace.yaml
  Certificates.yaml
  ServiceAccount.yaml
  Service.yaml
  ConfigMap.yaml
  Secret.yaml
  PersistentVolumeClaim.yaml
  PodDisruptionBudget.yaml
  NetworkPolicy.yaml
  StatefulSet.yaml
  Deployment.yaml
  Ingress.yaml
)

function apply() {
  for file in "${definitions[@]}"; do
    kubectl apply -f definitions/$file
  done
}

function delete() {
  kubectl delete -f definitions/Namespace.yaml
}

case "$1" in
  apply) apply ;;
  delete) delete ;;
esac
