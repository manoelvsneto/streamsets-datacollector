#!/bin/bash

# Test script para Dockerfile.ubuntu-debug
echo "🧪 Testando Dockerfile.ubuntu-debug"

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker não está rodando"
    exit 1
fi

echo "✅ Docker está rodando"

# Build the debug image
echo "🔨 Fazendo build da imagem debug..."
docker build -t streamsets-debug:test -f Dockerfile.ubuntu-debug . --no-cache

# Check build result
if [ $? -eq 0 ]; then
    echo "✅ Build concluído com sucesso!"
    
    # Show image details
    echo "📋 Detalhes da imagem:"
    docker images streamsets-debug:test
    
    # Test run container
    echo "🚀 Testando execução do container..."
    docker run --rm -d --name streamsets-test -p 18630:18630 streamsets-debug:test
    
    # Wait a bit for startup
    sleep 30
    
    # Check if container is running
    if docker ps | grep streamsets-test > /dev/null; then
        echo "✅ Container está rodando!"
        
        # Check health
        curl -f http://localhost:18630/ && echo "✅ Health check OK" || echo "⚠️ Health check falhou"
    else
        echo "❌ Container não está rodando"
        docker logs streamsets-test
    fi
    
    # Cleanup
    docker stop streamsets-test 2>/dev/null || true
    
else
    echo "❌ Build falhou!"
    exit 1
fi
