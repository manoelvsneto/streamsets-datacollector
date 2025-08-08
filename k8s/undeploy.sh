#!/bin/bash

# Script para remover o deployment do StreamSets Data Collector do Kubernetes
# Uso: ./undeploy.sh [development|production]

set -e

ENVIRONMENT=${1:-development}
NAMESPACE="streamsets"

if [ "$ENVIRONMENT" = "production" ]; then
    NAMESPACE="streamsets-prod"
fi

echo "🗑️ Removendo deployment do StreamSets Data Collector"
echo "📁 Ambiente: $ENVIRONMENT"
echo "📁 Namespace: $NAMESPACE"

# Verificar se kubectl está disponível
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl não encontrado. Instale o kubectl primeiro."
    exit 1
fi

# Confirmar remoção
read -p "❓ Tem certeza que deseja remover o deployment do ambiente $ENVIRONMENT? (y/N): " confirm
if [[ $confirm != [yY] ]]; then
    echo "❌ Operação cancelada."
    exit 0
fi

# Remover recursos na ordem correta
echo "🗑️ Removendo network policy..."
kubectl delete -f network-policy.yaml -n $NAMESPACE --ignore-not-found=true

echo "🗑️ Removendo HPA..."
kubectl delete -f hpa.yaml -n $NAMESPACE --ignore-not-found=true

echo "🗑️ Removendo ingress..."
kubectl delete -f ingress.yaml -n $NAMESPACE --ignore-not-found=true

echo "🗑️ Removendo serviços..."
kubectl delete -f service.yaml -n $NAMESPACE --ignore-not-found=true

echo "🗑️ Removendo deployment..."
kubectl delete -f deployment.yaml -n $NAMESPACE --ignore-not-found=true

# Aguardar pods serem removidos
echo "⏳ Aguardando pods serem removidos..."
kubectl wait --for=delete pods -l app=streamsets-datacollector -n $NAMESPACE --timeout=300s || true

echo "🗑️ Removendo armazenamento..."
kubectl delete -f persistent-volume.yaml -n $NAMESPACE --ignore-not-found=true

echo "🗑️ Removendo configurações..."
kubectl delete -f secret.yaml -n $NAMESPACE --ignore-not-found=true
kubectl delete -f configmap.yaml -n $NAMESPACE --ignore-not-found=true

# Perguntar se deseja remover o namespace
read -p "❓ Deseja remover o namespace $NAMESPACE? (y/N): " remove_ns
if [[ $remove_ns == [yY] ]]; then
    echo "🗑️ Removendo namespace..."
    kubectl delete namespace $NAMESPACE --ignore-not-found=true
fi

echo "✅ Remoção concluída com sucesso!"
