# StreamSets Data Collector - Kubernetes Deployment

Este diretório contém os manifestos Kubernetes para fazer o deploy do StreamSets Data Collector em um cluster Kubernetes.

## Estrutura dos Arquivos

- `namespace.yaml` - Namespace dedicado para o StreamSets
- `configmap.yaml` - Configurações da aplicação
- `secret.yaml` - Secrets para credenciais e configurações sensíveis
- `persistent-volume.yaml` - Persistent Volume Claims para armazenamento
- `deployment.yaml` - Deployment principal da aplicação
- `service.yaml` - Services para exposição da aplicação
- `ingress.yaml` - Ingress para acesso externo
- `hpa.yaml` - Horizontal Pod Autoscaler para auto-scaling
- `network-policy.yaml` - Políticas de rede para segurança
- `kustomization.yaml` - Configuração Kustomize para diferentes ambientes
- `deploy.sh` - Script para deployment automatizado
- `undeploy.sh` - Script para remoção do deployment

## Pré-requisitos

1. **Cluster Kubernetes** funcionando
2. **kubectl** configurado e conectado ao cluster
3. **Ingress Controller** instalado (nginx-ingress recomendado)
4. **Storage Class** configurada para Persistent Volumes
5. **Container Registry** (Azure Container Registry recomendado)

### Componentes Opcionais

- **cert-manager** para certificados SSL/TLS automáticos
- **Prometheus** para monitoramento
- **Grafana** para dashboards

## Configuração Inicial

### 1. Ajustar Configurações

Antes do deployment, ajuste as seguintes configurações:

#### `deployment.yaml`
```yaml
# Substitua pela URL do seu registry
image: yourregistry.azurecr.io/streamsets-datacollector:latest
```

#### `ingress.yaml`
```yaml
# Substitua pelo seu domínio
- host: streamsets.yourdomain.com
```

#### `persistent-volume.yaml`
```yaml
# Ajuste a storage class conforme seu cluster
storageClassName: default  # ou managed-premium, fast-ssd, etc.
```

### 2. Configurar Secrets

#### Credenciais do Registry (se necessário)
```bash
kubectl create secret docker-registry acr-secret \
  --docker-server=yourregistry.azurecr.io \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  -n streamsets
```

#### Atualizar Credenciais de Admin
```bash
# Gerar credenciais em base64
echo -n "seu_usuario" | base64
echo -n "sua_senha" | base64

# Atualizar secret.yaml com os valores gerados
```

## Deployment

### Deployment Automático

```bash
# Fazer permissão de execução
chmod +x deploy.sh undeploy.sh

# Deploy em desenvolvimento
./deploy.sh development

# Deploy em produção
./deploy.sh production
```

### Deployment Manual

```bash
# 1. Criar namespace
kubectl apply -f namespace.yaml

# 2. Aplicar configurações
kubectl apply -f configmap.yaml
kubectl apply -f secret.yaml

# 3. Configurar armazenamento
kubectl apply -f persistent-volume.yaml

# 4. Deploy da aplicação
kubectl apply -f deployment.yaml

# 5. Configurar serviços
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml

# 6. Configurar auto-scaling e segurança
kubectl apply -f hpa.yaml
kubectl apply -f network-policy.yaml
```

### Usando Kustomize

```bash
# Deploy com kustomize
kubectl apply -k .

# Para diferentes ambientes, crie overlays
mkdir -p overlays/production
# Configure overlays específicos para produção
```

## Verificação do Deployment

### Status dos Pods
```bash
kubectl get pods -n streamsets -l app=streamsets-datacollector
```

### Logs da Aplicação
```bash
kubectl logs -f deployment/streamsets-datacollector -n streamsets
```

### Status dos Serviços
```bash
kubectl get svc -n streamsets
kubectl get ingress -n streamsets
```

### Acesso Local (Desenvolvimento)
```bash
kubectl port-forward svc/streamsets-datacollector-service 18630:80 -n streamsets
# Acesse: http://localhost:18630
```

## Monitoramento e Troubleshooting

### Verificar Recursos
```bash
# Status geral
kubectl get all -n streamsets

# Eventos do namespace
kubectl get events -n streamsets --sort-by='.lastTimestamp'

# Describe do pod para detalhes
kubectl describe pod <pod-name> -n streamsets
```

### Verificar Storage
```bash
# Status dos PVCs
kubectl get pvc -n streamsets

# Detalhes de um PVC específico
kubectl describe pvc streamsets-data-pvc -n streamsets
```

### Verificar Configurações
```bash
# Ver ConfigMap
kubectl get configmap streamsets-config -o yaml -n streamsets

# Ver Secret (base64 encoded)
kubectl get secret streamsets-secret -o yaml -n streamsets
```

## Scaling

### Manual Scaling
```bash
# Escalar para 2 replicas
kubectl scale deployment streamsets-datacollector --replicas=2 -n streamsets
```

### Auto Scaling
O HPA está configurado para escalar baseado em CPU e memória:
- Min replicas: 1
- Max replicas: 3
- CPU target: 70%
- Memory target: 80%

## Backup e Restore

### Backup dos Dados
```bash
# Backup do PVC de dados
kubectl exec -n streamsets <pod-name> -- tar czf /tmp/backup.tar.gz /data

# Copiar backup para local
kubectl cp streamsets/<pod-name>:/tmp/backup.tar.gz ./backup.tar.gz
```

### Configurações de Backup Automático
Considere implementar:
- **Velero** para backup completo do cluster
- **Backup automático de PVs** via CSI snapshots
- **Backup de configurações** em Git

## Segurança

### Network Policies
As network policies limitam:
- Tráfego de entrada apenas do Ingress Controller
- Tráfego de saída apenas para DNS, HTTPS e bancos de dados específicos

### RBAC (a implementar)
```yaml
# Criar ServiceAccount específica
# Configurar RBAC com princípio de menor privilégio
```

### Pod Security Standards
```yaml
# Configurar Pod Security Standards
# Definir securityContext apropriado
```

## Configurações de Produção

### Recursos Recomendados
```yaml
resources:
  requests:
    memory: "4Gi"
    cpu: "1000m"
  limits:
    memory: "8Gi"
    cpu: "4000m"
```

### Storage para Produção
- Use storage classes com alta performance (SSD)
- Configure backup automático dos PVs
- Considere usar storage replicado

### Alta Disponibilidade
- Configure multiple AZs para o cluster
- Use node affinity para distribuir pods
- Configure PodDisruptionBudget

## Remoção

```bash
# Remover deployment
./undeploy.sh development

# Ou manual
kubectl delete -f .
kubectl delete namespace streamsets
```

## Troubleshooting Comum

### Pod não inicia
1. Verificar recursos disponíveis no cluster
2. Verificar se a imagem existe no registry
3. Verificar se os PVCs estão bound
4. Verificar logs: `kubectl logs <pod-name> -n streamsets`

### Não consegue acessar via Ingress
1. Verificar se o Ingress Controller está funcionando
2. Verificar configuração de DNS
3. Verificar certificados SSL
4. Verificar logs do Ingress Controller

### Performance Baixa
1. Verificar recursos de CPU/memória
2. Verificar performance do storage
3. Verificar configurações do SDC_JAVA_OPTS
4. Considerar scaling horizontal

### Problemas de Conectividade
1. Verificar Network Policies
2. Verificar DNS interno do cluster
3. Verificar configurações de firewall
4. Verificar conectividade com bancos de dados externos

## Suporte

Para mais informações:
- [Documentação StreamSets](https://docs.streamsets.com/)
- [Documentação Kubernetes](https://kubernetes.io/docs/)
- [Azure Kubernetes Service](https://docs.microsoft.com/azure/aks/)
