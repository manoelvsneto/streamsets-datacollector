Write-Host "🧪 Testando Dockerfile.ubuntu-debug" -ForegroundColor Green

# Check Docker is running
docker info | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker não está rodando" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Docker está rodando" -ForegroundColor Green

# Build the debug image
Write-Host "🔨 Fazendo build da imagem debug..." -ForegroundColor Yellow
docker build -t streamsets-debug:test -f Dockerfile.ubuntu-debug .

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Build concluído com sucesso!" -ForegroundColor Green
} else {
    Write-Host "❌ Build falhou!" -ForegroundColor Red
}
