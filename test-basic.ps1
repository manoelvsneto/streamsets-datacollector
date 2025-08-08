Write-Host "Testando Dockerfile.ubuntu-debug" -ForegroundColor Green

# Check Docker is running
docker info | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker nao esta rodando" -ForegroundColor Red
    exit 1
}

Write-Host "Docker esta rodando" -ForegroundColor Green

# Build the debug image
Write-Host "Fazendo build da imagem debug..." -ForegroundColor Yellow
docker build -t streamsets-debug:test -f Dockerfile.ubuntu-debug .

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build concluido com sucesso!" -ForegroundColor Green
} else {
    Write-Host "Build falhou!" -ForegroundColor Red
}
