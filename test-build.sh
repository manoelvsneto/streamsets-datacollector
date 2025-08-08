#!/bin/bash

# Script para testar o build Docker localmente
# Uso: ./test-build.sh [tag] [sdc_version] [sdc_libs] [ubuntu|fixed]

set -e

TAG=${1:-test-local}
SDC_VERSION=${2:-6.0.0-SNAPSHOT}
SDC_LIBS=${3:-streamsets-datacollector-jdbc-lib,streamsets-datacollector-jython_2_7-lib}
VARIANT=${4:-original}

if [ "$VARIANT" = "fixed" ]; then
    DOCKERFILE_PATH="Dockerfile.ubuntu-fixed"
    BASE_IMAGE="Ubuntu 22.04 (Certificados Corrigidos)"
elif [ "$VARIANT" = "ubuntu" ]; then
    DOCKERFILE_PATH="Dockerfile.ubuntu"
    BASE_IMAGE="Ubuntu 22.04"
else
    DOCKERFILE_PATH="Dockerfile"
    BASE_IMAGE="UBI9 OpenJDK 17"
fi

echo "🐳 Testando build Docker do StreamSets Data Collector"
echo "📦 Tag: $TAG"
echo "🔧 SDC Version: $SDC_VERSION"
echo "📚 SDC Libs: $SDC_LIBS"
echo "🐧 Base Image: $BASE_IMAGE"
echo "📄 Dockerfile: $DOCKERFILE_PATH"
echo ""

# Verificar se Docker está disponível
if ! command -v docker &> /dev/null; then
    echo "❌ Docker não encontrado. Instale o Docker primeiro."
    exit 1
fi

echo "✅ Docker disponível: $(docker --version)"

# Verificar se os arquivos necessários existem
REQUIRED_FILES=("$DOCKERFILE_PATH" "sdc-configure.sh")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ Arquivo $file não encontrado"
        exit 1
    fi
    echo "✅ Arquivo $file encontrado"
done

# Fazer o build
echo ""
echo "🔨 Iniciando build..."

if docker build \
    --build-arg SDC_VERSION="$SDC_VERSION" \
    --build-arg SDC_LIBS="$SDC_LIBS" \
    -f "$DOCKERFILE_PATH" \
    -t "streamsets-datacollector:$TAG" \
    .; then
    
    echo ""
    echo "✅ Build concluído com sucesso!"
    
    # Mostrar informações da imagem
    echo ""
    echo "📊 Informações da imagem:"
    docker images "streamsets-datacollector:$TAG"
    
    # Opção para testar a imagem
    echo ""
    read -p "🧪 Deseja testar a imagem? (y/N): " run_test
    if [[ $run_test =~ ^[Yy]$ ]]; then
        echo ""
        echo "🚀 Iniciando container de teste..."
        echo "🌐 Acesse: http://localhost:18630"
        echo "👤 Login: admin / admin"
        echo "⏹️  Para parar: Ctrl+C"
        echo ""
        
        trap 'echo ""; echo "🛑 Parando container..."; docker stop streamsets-test 2>/dev/null || true' INT
        
        docker run --rm -p 18630:18630 --name streamsets-test "streamsets-datacollector:$TAG"
    fi
else
    echo ""
    echo "❌ Erro durante o build"
    exit 1
fi

echo ""
echo "🧹 Para limpar a imagem de teste:"
echo "docker rmi streamsets-datacollector:$TAG"
