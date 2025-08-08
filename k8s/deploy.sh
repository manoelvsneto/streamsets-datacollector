#!/bin/bash

# Script para fazer deploy do StreamSets Data Collector no Kubernetes
# Uso: ./deploy.sh [development|production]

set -e

ENVIRONMENT=${1:-development}
NAMESPACE="streamsets"

if [ "$ENVIRONMENT" = "production" ]; then
    NAMESPACE="streamsets-prod"
fi

echo "🚀 Iniciando deployment do StreamSets Data Collector"
echo "📁 Ambiente: $ENVIRONMENT"
echo "📁 Namespace: $NAMESPACE"

# Verificar se kubectl está disponível
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl não encontrado. Instale o kubectl primeiro."
    exit 1
fi

# Verificar conexão com cluster
echo "🔍 Verificando conexão com cluster Kubernetes..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Não foi possível conectar ao cluster Kubernetes."
    exit 1
fi

echo "✅ Conectado ao cluster Kubernetes"

# Criar namespace se não existir
echo "📦 Criando namespace $NAMESPACE se não existir..."
kubectl apply -f namespace.yaml

# Aplicar configurações base
echo "⚙️ Aplicando configurações..."
kubectl apply -f configmap.yaml -n $NAMESPACE
kubectl apply -f secret.yaml -n $NAMESPACE

# Aplicar storage
echo "💾 Configurando armazenamento..."
kubectl apply -f persistent-volume.yaml -n $NAMESPACE

# Aguardar PVCs estarem prontos
echo "⏳ Aguardando PVCs estarem prontos..."
kubectl wait --for=condition=Bound pvc/streamsets-data-pvc -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=Bound pvc/streamsets-logs-pvc -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=Bound pvc/streamsets-resources-pvc -n $NAMESPACE --timeout=300s

# Aplicar deployment
echo "🚀 Fazendo deployment da aplicação..."
kubectl apply -f deployment.yaml -n $NAMESPACE

# Aguardar deployment estar pronto
echo "⏳ Aguardando deployment estar pronto..."
kubectl wait --for=condition=Available deployment/streamsets-datacollector -n $NAMESPACE --timeout=600s

# Aplicar serviços
echo "🌐 Configurando serviços..."
kubectl apply -f service.yaml -n $NAMESPACE

# Aplicar ingress (apenas se não for desenvolvimento local)
if [ "$ENVIRONMENT" != "local" ]; then
    echo "🌍 Configurando ingress..."
    kubectl apply -f ingress.yaml -n $NAMESPACE
fi

# Aplicar HPA
echo "📈 Configurando auto-scaling..."
kubectl apply -f hpa.yaml -n $NAMESPACE

# Aplicar network policy
echo "🔒 Aplicando políticas de rede..."
kubectl apply -f network-policy.yaml -n $NAMESPACE

echo "✅ Deploy concluído com sucesso!"

# Mostrar status
echo ""
echo "📊 Status do deployment:"
kubectl get pods -n $NAMESPACE -l app=streamsets-datacollector
echo ""
kubectl get svc -n $NAMESPACE -l app=streamsets-datacollector
echo ""

# Obter URL de acesso
if [ "$ENVIRONMENT" != "local" ]; then
    echo "🌍 URLs de acesso:"
    kubectl get ingress -n $NAMESPACE
else
    echo "🌍 Para acessar localmente, execute:"
    echo "kubectl port-forward svc/streamsets-datacollector-service 18630:80 -n $NAMESPACE"
    echo "Acesse: http://localhost:18630"
fi

echo ""
echo "🔍 Para verificar logs:"
echo "kubectl logs -f deployment/streamsets-datacollector -n $NAMESPACE"

echo ""
echo "🗑️ Para remover o deployment:"
echo "./undeploy.sh $ENVIRONMENT"
