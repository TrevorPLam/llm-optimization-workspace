# Quick Server Test
Set-Location "c:\Users\trevo\Desktop\LLM_Optimization_Workspace\Scripts"

# Load the testing framework
. .\server_testing_framework.ps1

# Test model discovery
Write-Host "Testing model discovery..." -ForegroundColor Yellow
$models = Initialize-TestModels

if ($models) {
    Write-Host "Models found: $($script:TestModels.Count)" -ForegroundColor Green
    $script:TestModels | ForEach-Object {
        Write-Host "  - $($_.Name) ($($_.Size)MB)" -ForegroundColor Gray
    }
    
    # Get the fastest model
    $testModel = Get-OptimalTestModel -Preference "fastest"
    Write-Host "Using test model: $($testModel.Name)" -ForegroundColor Cyan
    
    # Test server dependencies with absolute path
    Write-Host "`nTesting server dependencies..." -ForegroundColor Yellow
    $scriptDir = Split-Path $PSScriptRoot -Parent
    $serverPath = Join-Path $scriptDir "Tools\bin\llama-server.exe"
    $depTest = Test-ServerDependencies -ServerPath $serverPath
    
    if ($depTest.Success) {
        Write-Host "Dependencies OK, starting server test..." -ForegroundColor Green
        
        # Run a basic server test (without performance monitoring for speed)
        $result = Invoke-CompleteServerTest -ModelPath $testModel.Path -Port 8081 -Detailed
        
        if ($result.OverallSuccess) {
            Write-Host "✅ Server test completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "❌ Server test failed: $($result.Error)" -ForegroundColor Red
        }
    } else {
        Write-Host "❌ Dependency test failed" -ForegroundColor Red
    }
} else {
    Write-Host "❌ No models found" -ForegroundColor Red
}
