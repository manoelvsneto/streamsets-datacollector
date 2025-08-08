# Script PowerShell para build multi-arquitetura do StreamSets Data Collector
# Usa Docker Buildx para suporte ARM64 e AMD64
# Uso: .\build-multiarch.ps1 [-Tag "latest"] [-Push]

param(
    [string]$Tag = "latest",
    [switch]$Push,
    [string]$Registry = "manoelvsneto"
)

$ImageName = "streamsets-datacollector"
$FullImage = "$Registry/$ImageName"

Write-Host "🚀 Build Multi-arquitetura do StreamSets Data Collector" -ForegroundColor Green
Write-Host "🏷️  Tag: $Tag" -ForegroundColor Yellow
Write-Host "📦 Imagem: $FullImage`:$Tag" -ForegroundColor Yellow
Write-Host "🔄 Push: $Push" -ForegroundColor Yellow
Write-Host ""

# Verificar se Docker Buildx está disponível
try {
    $buildxVersion = docker buildx version
    Write-Host "✅ Docker Buildx disponível: $buildxVersion" -ForegroundColor Green
}
catch {
    Write-Host "❌ Docker Buildx não encontrado." -ForegroundColor Red
    Write-Host "💡 Instale o Docker Desktop ou configure buildx:" -ForegroundColor Yellow
    Write-Host "   docker buildx install" -ForegroundColor Gray
    exit 1
}

# Verificar se os arquivos necessários existem
$RequiredFiles = @("Dockerfile.multiarch", "sdc-configure.sh", "docker-entrypoint.sh")
foreach ($file in $RequiredFiles) {
    if (!(Test-Path $file)) {
        Write-Host "❌ Arquivo $file não encontrado" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Arquivo $file encontrado" -ForegroundColor Green
}

# Criar builder multi-plataforma se não existir
$BuilderName = "streamsets-builder"
$builderExists = $false
try {
    docker buildx inspect $BuilderName | Out-Null
    $builderExists = $true
}
catch {
    Write-Host "🔧 Criando builder multi-plataforma..." -ForegroundColor Cyan
    docker buildx create --name $BuilderName --driver docker-container --bootstrap
}

if ($builderExists) {
    Write-Host "🔧 Builder $BuilderName já existe" -ForegroundColor Green
}

Write-Host "🔧 Usando builder: $BuilderName" -ForegroundColor Cyan
docker buildx use $BuilderName

# Configurar argumentos de build
$BuildArgs = @(
    "--platform=linux/amd64,linux/arm64",
    "--file=Dockerfile.multiarch",
    "--build-arg=SDC_VERSION=6.0.0-SNAPSHOT",
    "--build-arg=SDC_LIBS=streamsets-datacollector-jdbc-lib,streamsets-datacollector-jython_2_7-lib",
    "--tag=$FullImage`:$Tag"
)

# Adicionar latest tag se não for latest
if ($Tag -ne "latest") {
    $BuildArgs += "--tag=$FullImage`:latest"
}

# Adicionar push se solicitado
if ($Push) {
    $BuildArgs += "--push"
    Write-Host "📤 Imagem será enviada para o registry" -ForegroundColor Cyan
} else {
    $BuildArgs += "--load"
    Write-Host "💾 Imagem será carregada localmente (apenas AMD64)" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "🔨 Iniciando build multi-arquitetura..." -ForegroundColor Cyan
Write-Host "🎯 Plataformas: linux/amd64, linux/arm64" -ForegroundColor Yellow

# Executar build
try {
    $BuildArgs += "."
    & docker buildx build $BuildArgs
    
    Write-Host ""
    Write-Host "✅ Build multi-arquitetura concluído com sucesso!" -ForegroundColor Green
    
    if ($Push) {
        Write-Host "📤 Imagem disponível em: $FullImage`:$Tag" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "🧪 Para testar:" -ForegroundColor Yellow
        Write-Host "# AMD64:" -ForegroundColor Gray
        Write-Host "docker run --rm -p 18630:18630 --platform linux/amd64 $FullImage`:$Tag" -ForegroundColor Gray
        Write-Host ""
        Write-Host "# ARM64:" -ForegroundColor Gray
        Write-Host "docker run --rm -p 18630:18630 --platform linux/arm64 $FullImage`:$Tag" -ForegroundColor Gray
    } else {
        Write-Host "💾 Imagem carregada localmente" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "🧪 Para testar:" -ForegroundColor Yellow
        Write-Host "docker run --rm -p 18630:18630 $FullImage`:$Tag" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "🌐 Acesse: http://localhost:18630" -ForegroundColor Green
    Write-Host "👤 Login: admin / admin" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "❌ Erro durante o build multi-arquitetura" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🔍 Para inspecionar a imagem:" -ForegroundColor Yellow
Write-Host "docker buildx imagetools inspect $FullImage`:$Tag" -ForegroundColor Gray

Write-Host ""
Write-Host "🧹 Para limpar o builder:" -ForegroundColor Yellow
Write-Host "docker buildx rm $BuilderName" -ForegroundColor Gray
