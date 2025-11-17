#!/bin/bash
set -e

# Install ArgoCD in the Kubernetes cluster

# Create namespace and apply ArgoCD manifests
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# verify installation
kubectl get pods -n argocd