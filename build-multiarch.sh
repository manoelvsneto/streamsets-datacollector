#!/bin/bash

# Script para build multi-arquitetura do StreamSets Data Collector
# Usa Docker Buildx para suporte ARM64 e AMD64
# Uso: ./build-multiarch.sh [tag] [push]

set -e

TAG=${1:-latest}
PUSH=${2:-false}
REGISTRY=${REGISTRY:-manoelvsneto}
IMAGE_NAME="streamsets-datacollector"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}"

echo "🚀 Build Multi-arquitetura do StreamSets Data Collector"
echo "🏷️  Tag: $TAG"
echo "📦 Imagem: $FULL_IMAGE:$TAG"
echo "🔄 Push: $PUSH"
echo ""

# Verificar se Docker Buildx está disponível
if ! docker buildx version &> /dev/null; then
    echo "❌ Docker Buildx não encontrado."
    echo "💡 Instale o Docker Desktop ou configure buildx:"
    echo "   docker buildx install"
    exit 1
fi

echo "✅ Docker Buildx disponível: $(docker buildx version)"

# Verificar se os arquivos necessários existem
REQUIRED_FILES=("Dockerfile.multiarch" "sdc-configure.sh" "docker-entrypoint.sh")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ Arquivo $file não encontrado"
        exit 1
    fi
    echo "✅ Arquivo $file encontrado"
done

# Criar builder multi-plataforma se não existir
BUILDER_NAME="streamsets-builder"
if ! docker buildx inspect $BUILDER_NAME &> /dev/null; then
    echo "🔧 Criando builder multi-plataforma..."
    docker buildx create --name $BUILDER_NAME --driver docker-container --bootstrap
fi

echo "🔧 Usando builder: $BUILDER_NAME"
docker buildx use $BUILDER_NAME

# Configurar argumentos de build
BUILD_ARGS=(
    "--platform=linux/amd64,linux/arm64"
    "--file=Dockerfile.multiarch"
    "--build-arg=SDC_VERSION=6.0.0-SNAPSHOT"
    "--build-arg=SDC_LIBS=streamsets-datacollector-jdbc-lib,streamsets-datacollector-jython_2_7-lib"
    "--tag=$FULL_IMAGE:$TAG"
)

# Adicionar latest tag se não for latest
if [ "$TAG" != "latest" ]; then
    BUILD_ARGS+=("--tag=$FULL_IMAGE:latest")
fi

# Adicionar push se solicitado
if [ "$PUSH" = "true" ] || [ "$PUSH" = "push" ]; then
    BUILD_ARGS+=("--push")
    echo "📤 Imagem será enviada para o registry"
else
    BUILD_ARGS+=("--load")
    echo "💾 Imagem será carregada localmente (apenas AMD64)"
fi

echo ""
echo "🔨 Iniciando build multi-arquitetura..."
echo "🎯 Plataformas: linux/amd64, linux/arm64"

# Executar build
if docker buildx build "${BUILD_ARGS[@]}" .; then
    echo ""
    echo "✅ Build multi-arquitetura concluído com sucesso!"
    
    if [ "$PUSH" = "true" ] || [ "$PUSH" = "push" ]; then
        echo "📤 Imagem disponível em: $FULL_IMAGE:$TAG"
        echo ""
        echo "🧪 Para testar:"
        echo "# AMD64:"
        echo "docker run --rm -p 18630:18630 --platform linux/amd64 $FULL_IMAGE:$TAG"
        echo ""
        echo "# ARM64:"
        echo "docker run --rm -p 18630:18630 --platform linux/arm64 $FULL_IMAGE:$TAG"
    else
        echo "💾 Imagem carregada localmente"
        echo ""
        echo "🧪 Para testar:"
        echo "docker run --rm -p 18630:18630 $FULL_IMAGE:$TAG"
    fi
    
    echo ""
    echo "🌐 Acesse: http://localhost:18630"
    echo "👤 Login: admin / admin"
    
else
    echo ""
    echo "❌ Erro durante o build multi-arquitetura"
    exit 1
fi

echo ""
echo "🔍 Para inspecionar a imagem:"
echo "docker buildx imagetools inspect $FULL_IMAGE:$TAG"

echo ""
echo "🧹 Para limpar o builder:"
echo "docker buildx rm $BUILDER_NAME"
