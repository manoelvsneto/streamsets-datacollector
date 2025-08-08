#!/bin/bash

# Script de troubleshooting para problemas de certificados Java
# Uso: ./debug-java-certs.sh [image-tag]

set -e

IMAGE_TAG=${1:-streamsets-datacollector:test-local}

echo "🔍 Debug de Certificados Java - StreamSets Data Collector"
echo "🏷️  Imagem: $IMAGE_TAG"
echo ""

# Verificar se a imagem existe
if ! docker image inspect "$IMAGE_TAG" &> /dev/null; then
    echo "❌ Imagem $IMAGE_TAG não encontrada"
    echo "💡 Execute o build primeiro:"
    echo "   ./test-build.sh test-local 6.0.0-SNAPSHOT \"jdbc,jython\" fixed"
    exit 1
fi

echo "✅ Imagem encontrada: $IMAGE_TAG"

# Função para executar comandos no container
run_in_container() {
    local cmd="$1"
    local description="$2"
    
    echo ""
    echo "🔧 $description"
    echo "📝 Comando: $cmd"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if docker run --rm "$IMAGE_TAG" bash -c "$cmd" 2>/dev/null; then
        echo "✅ Sucesso"
    else
        echo "❌ Falhou"
        echo "🔍 Tentando com mais detalhes..."
        docker run --rm "$IMAGE_TAG" bash -c "$cmd" || true
    fi
}

# Verificações básicas
run_in_container "uname -m" "Verificar arquitetura do container"
run_in_container "java -version" "Verificar versão do Java"
run_in_container "echo \$JAVA_HOME" "Verificar JAVA_HOME"

# Verificações de certificados
run_in_container "ls -la /etc/ssl/certs/java/" "Verificar diretório de certificados Java"
run_in_container "ls -la \$JAVA_HOME/lib/security/" "Verificar diretório security do Java"

# Verificar cacerts
run_in_container "file /etc/ssl/certs/java/cacerts" "Verificar arquivo cacerts"
run_in_container "ls -la /etc/ssl/certs/java/cacerts" "Verificar permissões do cacerts"

# Testar acesso aos certificados
run_in_container "keytool -list -keystore /etc/ssl/certs/java/cacerts -storepass changeit | head -5" "Testar leitura do keystore"

# Verificar certificados instalados
run_in_container "keytool -list -keystore /etc/ssl/certs/java/cacerts -storepass changeit | grep -i 'Certificate fingerprint' | wc -l" "Contar certificados instalados"

# Verificar conectividade HTTPS
run_in_container "curl -I https://www.google.com" "Testar conectividade HTTPS"

# Verificar se StreamSets consegue acessar certificados
echo ""
echo "🚀 Testando inicialização do StreamSets..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Executar container temporário em background
CONTAINER_ID=$(docker run -d --name streamsets-debug "$IMAGE_TAG")

# Aguardar alguns segundos
echo "⏳ Aguardando inicialização..."
sleep 10

# Verificar logs
echo "📋 Logs de inicialização:"
docker logs "$CONTAINER_ID" 2>&1 | head -30

# Verificar se há erros relacionados a certificados
if docker logs "$CONTAINER_ID" 2>&1 | grep -i "certificate\|ssl\|tls\|keystore" > /dev/null; then
    echo ""
    echo "⚠️  Encontrados logs relacionados a certificados:"
    docker logs "$CONTAINER_ID" 2>&1 | grep -i "certificate\|ssl\|tls\|keystore"
else
    echo "✅ Nenhum erro de certificado encontrado nos logs"
fi

# Cleanup
docker stop "$CONTAINER_ID" > /dev/null 2>&1 || true
docker rm "$CONTAINER_ID" > /dev/null 2>&1 || true

echo ""
echo "🔍 Análise completa!"
echo ""
echo "💡 Soluções para problemas comuns:"
echo ""
echo "1. ❌ Arquivo cacerts não encontrado:"
echo "   - Use Dockerfile.ubuntu-fixed"
echo "   - Executa: mkdir -p /etc/ssl/certs/java antes da instalação"
echo ""
echo "2. ❌ Permissões incorretas:"
echo "   - Adiciona: chmod 755 /etc/ssl/certs/java"
echo "   - Reconfigura: dpkg-reconfigure ca-certificates-java"
echo ""
echo "3. ❌ Certificados não carregados:"
echo "   - Executa: /var/lib/dpkg/info/ca-certificates-java.postinst configure"
echo ""
echo "4. ❌ JAVA_HOME incorreto para ARM64:"
echo "   - ARM64: /usr/lib/jvm/java-17-openjdk-arm64"
echo "   - AMD64: /usr/lib/jvm/java-17-openjdk-amd64"
echo ""
echo "🧪 Para testar a versão corrigida:"
echo "   ./test-build.sh test-fixed 6.0.0-SNAPSHOT \"jdbc,jython\" fixed"
