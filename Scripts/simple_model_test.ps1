# Simple Model Test Script
param(
    [string]$ModelPath,
    [string]$MainBinary = ".\Tools\bin\main.exe",
    [int]$MaxTokens = 50
)

Write-Host "Testing model: $ModelPath"

if (-not (Test-Path $ModelPath)) {
    Write-Host "❌ Model file not found: $ModelPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $MainBinary)) {
    Write-Host "❌ Binary not found: $MainBinary" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "🔄 Testing model loading..." -ForegroundColor Yellow
    
    $loadArgs = @(
        "-m", $ModelPath,
        "-n", "1",
        "--log-disable",
        "--quiet"
    )
    
    $loadProcess = Start-Process -FilePath $MainBinary -ArgumentList $loadArgs -NoNewWindow -PassThru -Wait
    
    if ($loadProcess.ExitCode -ne 0) {
        Write-Host "❌ Model loading failed with exit code: $($loadProcess.ExitCode)" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✅ Model loading successful" -ForegroundColor Green
    
    Write-Host "🔄 Testing text generation..." -ForegroundColor Yellow
    
    $genArgs = @(
        "-m", $ModelPath,
        "-p", "Hello, how are you?",
        "-n", $MaxTokens,
        "--log-disable",
        "-t", "1",
        "--ctx-size", "2048"
    )
    
    $genProcess = Start-Process -FilePath $MainBinary -ArgumentList $genArgs -NoNewWindow -PassThru -Wait
    
    if ($genProcess.ExitCode -ne 0) {
        Write-Host "❌ Text generation failed with exit code: $($genProcess.ExitCode)" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✅ Text generation successful" -ForegroundColor Green
    Write-Host "🎉 Model test passed!" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
