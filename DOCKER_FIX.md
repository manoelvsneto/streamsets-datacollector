# Fix para Erro de Permissão no Docker Build

## Problema Identificado

Durante o build da imagem Docker, ocorria o seguinte erro:

```
#15 0.169 /bin/sh: line 1: /tmp/sdc-configure.sh: Permission denied
#15 ERROR: process "/bin/sh -c /tmp/sdc-configure.sh" did not complete successfully: exit code: 126
```

## Causa

O arquivo `sdc-configure.sh` estava sendo copiado para o container sem permissão de execução, causando falha na etapa de configuração.

## Solução Aplicada

**Antes:**
```dockerfile
# Run the SDC configuration script.
COPY sdc-configure.sh *.tgz /tmp/
RUN /tmp/sdc-configure.sh
```

**Depois:**
```dockerfile
# Run the SDC configuration script.
COPY sdc-configure.sh *.tgz /tmp/
RUN chmod +x /tmp/sdc-configure.sh && /tmp/sdc-configure.sh
```

## Mudanças Realizadas

### 1. Dockerfile
- ✅ Adicionado `chmod +x` antes de executar o script de configuração

### 2. Azure Pipeline
- ✅ Atualizado para usar `Kubernetes@1` task em vez da versão deprecated
- ✅ Adicionado deploy de namespace explícito
- ✅ Configurado para Docker Hub (`manoelvsneto/streamsets-datacollector`)

### 3. Manifests Kubernetes
- ✅ Atualizado deployment para usar a imagem correta do Docker Hub
- ✅ Ajustado HPA para `maxReplicas: 1` (natureza stateful do StreamSets)
- ✅ Configurado ingress para domínio `streamsets.archse.eng.br`

### 4. Scripts de Teste
- ✅ Criado `test-build.ps1` para testar build no Windows
- ✅ Criado `test-build.sh` para testar build no Linux
- ✅ Ambos scripts incluem opção de teste interativo

## Como Testar o Fix

### Windows (PowerShell)
```powershell
.\test-build.ps1
```

### Linux/Mac (Bash)
```bash
chmod +x test-build.sh
./test-build.sh
```

### Teste Manual
```bash
# Build da imagem
docker build --build-arg SDC_VERSION=6.0.0-SNAPSHOT \
  --build-arg SDC_LIBS=streamsets-datacollector-jdbc-lib,streamsets-datacollector-jython_2_7-lib \
  -t streamsets-datacollector:test .

# Teste local
docker run --rm -p 18630:18630 streamsets-datacollector:test

# Acesse: http://localhost:18630
# Login: admin / admin
```

## Próximos Passos

1. ✅ **Build corrigido** - Problema de permissão resolvido
2. 🔄 **Pipeline atualizado** - Azure DevOps configurado
3. 🔄 **Deploy K8s** - Manifests prontos para uso
4. ⏳ **Teste produção** - Aguardando deploy real

## Notas Importantes

- O StreamSets Data Collector é uma aplicação **stateful**, por isso o HPA está limitado a 1 replica
- Para scaling horizontal, considere usar múltiplas instâncias com **data volumes separados**
- As configurações atuais são adequadas para **single-instance deployment**
- Para **alta disponibilidade**, será necessário configurar **load balancing** e **shared storage**
