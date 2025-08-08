# Script PowerShell para testar o build Docker localmente
# Uso: .\test-build.ps1

param(
    [string]$Tag = "test-local",
    [string]$SdcVersion = "6.0.0-SNAPSHOT",
    [string]$SdcLibs = "streamsets-datacollector-jdbc-lib,streamsets-datacollector-jython_2_7-lib"
)

Write-Host "🐳 Testando build Docker do StreamSets Data Collector" -ForegroundColor Green
Write-Host "📦 Tag: $Tag" -ForegroundColor Yellow
Write-Host "🔧 SDC Version: $SdcVersion" -ForegroundColor Yellow
Write-Host "📚 SDC Libs: $SdcLibs" -ForegroundColor Yellow
Write-Host ""

# Verificar se Docker está disponível
try {
    docker --version | Out-Host
    Write-Host "✅ Docker disponível" -ForegroundColor Green
}
catch {
    Write-Host "❌ Docker não encontrado. Instale o Docker Desktop primeiro." -ForegroundColor Red
    exit 1
}

# Verificar se os arquivos necessários existem
$requiredFiles = @("Dockerfile", "sdc-configure.sh")
foreach ($file in $requiredFiles) {
    if (!(Test-Path $file)) {
        Write-Host "❌ Arquivo $file não encontrado" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Arquivo $file encontrado" -ForegroundColor Green
}

# Fazer o build
Write-Host ""
Write-Host "🔨 Iniciando build..." -ForegroundColor Cyan

$buildArgs = @(
    "--build-arg", "SDC_VERSION=$SdcVersion",
    "--build-arg", "SDC_LIBS=$SdcLibs",
    "-t", "streamsets-datacollector:$Tag",
    "."
)

try {
    docker build @buildArgs
    Write-Host ""
    Write-Host "✅ Build concluído com sucesso!" -ForegroundColor Green
    
    # Mostrar informações da imagem
    Write-Host ""
    Write-Host "📊 Informações da imagem:" -ForegroundColor Cyan
    docker images streamsets-datacollector:$Tag
    
    # Opção para testar a imagem
    $runTest = Read-Host "`n🧪 Deseja testar a imagem? (y/N)"
    if ($runTest -eq "y" -or $runTest -eq "Y") {
        Write-Host ""
        Write-Host "🚀 Iniciando container de teste..." -ForegroundColor Cyan
        Write-Host "🌐 Acesse: http://localhost:18630" -ForegroundColor Yellow
        Write-Host "👤 Login: admin / admin" -ForegroundColor Yellow
        Write-Host "⏹️  Para parar: Ctrl+C" -ForegroundColor Yellow
        Write-Host ""
        
        docker run --rm -p 18630:18630 --name streamsets-test streamsets-datacollector:$Tag
    }
}
catch {
    Write-Host ""
    Write-Host "❌ Erro durante o build:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🧹 Para limpar a imagem de teste:" -ForegroundColor Yellow
Write-Host "docker rmi streamsets-datacollector:$Tag" -ForegroundColor Gray
