# Test script PowerShell para Dockerfile.ubuntu-debug
Write-Host "🧪 Testando Dockerfile.ubuntu-debug" -ForegroundColor Green

# Check Docker is running
try {
    docker info | Out-Null
    Write-Host "✅ Docker está rodando" -ForegroundColor Green
}
catch {
    Write-Host "❌ Docker não está rodando" -ForegroundColor Red
    exit 1
}

# Build the debug image
Write-Host "🔨 Fazendo build da imagem debug..." -ForegroundColor Yellow
docker build -t streamsets-debug:test -f Dockerfile.ubuntu-debug . --no-cache

# Check build result
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Build concluído com sucesso!" -ForegroundColor Green
    
    # Show image details
    Write-Host "📋 Detalhes da imagem:" -ForegroundColor Cyan
    docker images streamsets-debug:test
    
    # Test run container
    Write-Host "🚀 Testando execução do container..." -ForegroundColor Yellow
    docker run --rm -d --name streamsets-test -p 18630:18630 streamsets-debug:test
    
    # Wait a bit for startup
    Start-Sleep -Seconds 30
    
    # Check if container is running
    $containerRunning = docker ps | Select-String "streamsets-test"
    if ($containerRunning) {
        Write-Host "✅ Container está rodando!" -ForegroundColor Green
        
        # Check health
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:18630/" -UseBasicParsing -TimeoutSec 10
            Write-Host "✅ Health check OK" -ForegroundColor Green
        }
        catch {
            Write-Host "⚠️ Health check falhou: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "❌ Container não está rodando" -ForegroundColor Red
        docker logs streamsets-test
    }
    
    # Cleanup
    docker stop streamsets-test 2>$null
}
else {
    Write-Host "❌ Build falhou!" -ForegroundColor Red
    exit 1
}
