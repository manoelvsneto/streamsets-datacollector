# Fix para Erro de Certificados Java no Ubuntu 22.04

## 🚨 Problema Identificado

Durante o build da imagem Docker baseada em Ubuntu 22.04, ocorria o seguinte erro:

```
#6 27.00 head: cannot open '/etc/ssl/certs/java/cacerts' for reading: No such file or directory
```

Este erro acontece durante a instalação do pacote `ca-certificates-java`.

## 🔍 Causa Raiz

O pacote `ca-certificates-java` tenta acessar o diretório `/etc/ssl/certs/java/` e o arquivo `cacerts` antes deles serem criados. Isso ocorre porque:

1. O OpenJDK é instalado primeiro
2. O pacote `ca-certificates-java` é instalado depois
3. Durante a instalação, o script postinst tenta acessar um diretório que ainda não existe
4. O diretório só é criado durante a configuração dos certificados

## ✅ Solução Implementada

### 1. Dockerfile.ubuntu-fixed

Criado uma versão corrigida com a seguinte sequência:

```dockerfile
# 1. Instalar utilitários básicos e certificados base
RUN apt-get update && \
    apt-get install -y \
        curl wget unzip sudo hostname iputils-ping \
        traceroute psmisc gnupg lsb-release ca-certificates && \
    
    # 2. Instalar Java JRE
    apt-get install -y openjdk-17-jre-headless && \
    
    # 3. Criar diretório de certificados Java ANTES da instalação
    mkdir -p /etc/ssl/certs/java && \
    chmod 755 /etc/ssl/certs/java && \
    
    # 4. Instalar pacote de certificados Java
    apt-get install -y ca-certificates-java && \
    
    # 5. Forçar reconfiguração para garantir que tudo funcione
    dpkg-reconfigure -f noninteractive ca-certificates-java
```

### 2. Verificação Adicional

```dockerfile
# Verificar que tudo foi instalado corretamente
RUN java -version && \
    ls -la /etc/ssl/certs/java/ && \
    keytool -list -keystore /etc/ssl/certs/java/cacerts -storepass changeit | head -10
```

## 🧪 Como Testar

### Teste da Versão Corrigida

**Windows:**
```powershell
# Teste da versão corrigida
.\test-build.ps1 -Tag "test-fixed" -Fixed

# Ou versão original para comparar
.\test-build.ps1 -Tag "test-ubuntu" -Ubuntu
```

**Linux/Mac:**
```bash
# Teste da versão corrigida
./test-build.sh test-fixed 6.0.0-SNAPSHOT "jdbc,jython" fixed

# Ou versão original para comparar  
./test-build.sh test-ubuntu 6.0.0-SNAPSHOT "jdbc,jython" ubuntu
```

### Debug de Certificados

```bash
# Script específico para debug
chmod +x debug-java-certs.sh
./debug-java-certs.sh streamsets-datacollector:test-fixed
```

## 📊 Comparação das Versões

| Aspecto | Dockerfile.ubuntu | Dockerfile.ubuntu-fixed |
|---------|-------------------|--------------------------|
| **Ordem de instalação** | Java → ca-certificates-java | Básicos → Java → mkdir → ca-certificates-java |
| **Diretório /etc/ssl/certs/java** | Criado automaticamente | Criado manualmente antes |
| **Reconfigurração** | Automática | Forçada com dpkg-reconfigure |
| **Verificação** | Nenhuma | Testa Java e certificados |
| **Sucesso do build** | ❌ Falha | ✅ Sucesso |

## 🔧 Pipeline Atualizado

O `azure-pipelines.yml` foi atualizado para usar a versão corrigida:

```yaml
variables:
  dockerfilePath: '$(Build.SourcesDirectory)/Dockerfile.ubuntu-fixed'
```

## ⚡ Otimizações Adicionais

### 1. Java Container Support
```dockerfile
ENV SDC_JAVA_OPTS="-Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
```

### 2. Health Check
```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:18630/ || exit 1
```

### 3. Labels para Metadados
```dockerfile
LABEL org.label-schema.name="StreamSets Data Collector Ubuntu" \
      org.label-schema.description="StreamSets Data Collector on Ubuntu 22.04" \
      org.label-schema.version="${SDC_VERSION}"
```

## 🌟 Benefícios da Correção

1. ✅ **Build confiável** - Não falha mais com erro de certificados
2. ✅ **Certificados funcionais** - Java pode acessar HTTPS corretamente  
3. ✅ **Multi-arquitetura** - Funciona em AMD64 e ARM64
4. ✅ **Verificação automática** - Testa certificados durante build
5. ✅ **Debug facilitado** - Script de troubleshooting incluído

## 🚀 Próximos Passos

1. ✅ **Dockerfile corrigido** - `Dockerfile.ubuntu-fixed` criado
2. ✅ **Pipeline atualizado** - Usando versão corrigida
3. ✅ **Scripts de teste** - Suportam nova versão
4. ✅ **Debug script** - Para troubleshooting
5. 🔄 **Teste em produção** - Deploy e validação

## 📞 Troubleshooting

### Se ainda houver problemas:

1. **Execute o debug script:**
   ```bash
   ./debug-java-certs.sh your-image:tag
   ```

2. **Verifique logs do container:**
   ```bash
   docker logs container-name 2>&1 | grep -i certificate
   ```

3. **Teste certificados manualmente:**
   ```bash
   docker run --rm your-image keytool -list -keystore /etc/ssl/certs/java/cacerts -storepass changeit
   ```

4. **Verifique HTTPS:**
   ```bash
   docker run --rm your-image curl -I https://www.google.com
   ```

## 🎯 Resumo

A correção resolve definitivamente o problema de certificados Java no Ubuntu 22.04, garantindo que:
- O diretório de certificados seja criado antes da instalação
- Os certificados sejam configurados corretamente
- O build seja confiável e reproduzível
- Funcione em ambas as arquiteturas (AMD64 e ARM64)
