# Comprehensive Model Testing Framework
# Tests all 72 GGUF models for functionality, performance, and compatibility

param(
    [string]$TestCategory = "all",
    [string]$MainBinary = ".\Tools\bin\main.exe",
    [string]$ServerBinary = ".\Tools\bin\llama-server.exe",
    [int]$MaxTokens = 50,
    [int]$TimeoutSeconds = 30,
    [switch]$Verbose,
    [switch]$GenerateReport
)

# Initialize testing environment
$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# Test results storage
$TestResults = @()
$FailedModels = @()
$SuccessfulModels = @()
$PerformanceMetrics = @()

# Logging setup
$LogDir = ".\Scripts\Logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = Join-Path $LogDir "model_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
    if ($Verbose -or $Level -eq "ERROR") {
        Write-Host $logEntry -ForegroundColor $(if($Level -eq "ERROR") {"Red"} elseif($Level -eq "WARNING") {"Yellow"} else {"Green"})
    }
}

function Test-BinaryAvailability {
    Write-Log "Checking binary availability..."
    
    $binaries = @(
        @{Path = $MainBinary; Name = "main.exe"},
        @{Path = $ServerBinary; Name = "llama-server.exe"}
    )
    
    foreach ($binary in $binaries) {
        if (-not (Test-Path $binary.Path)) {
            Write-Log "Binary not found: $($binary.Path)" -Level "ERROR"
            throw "Required binary missing: $($binary.Name)"
        }
        Write-Log "✓ Binary found: $($binary.Name)"
    }
}

function Get-ModelCategories {
    $models = @{}
    
    # Ultra-Lightweight
    $models.ultra_lightweight = @(
        ".\Tools\models\ultra-lightweight\Qwen2.5-0.5B-Instruct-Q4_K_M.gguf",
        ".\Tools\models\ultra-lightweight\tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
    )
    
    # Small Elite
    $models.small_elite = @(
        ".\Tools\models\small-elite\Qwen3.5-0.8B-Q4_K_M.gguf",
        ".\Tools\models\small-elite\gemma-3-1b-it-Q4_K_M.gguf",
        ".\Tools\models\small-elite\llama-3.2-1b-instruct-q4_k_m.gguf",
        ".\Tools\models\small-elite\qwen2.5-1.5b-instruct-q4_k_m.gguf",
        ".\Tools\models\small-elite\qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
        ".\Tools\models\small-elite\smolLM2-1.7b-instruct-q4_k_m.gguf"
    )
    
    # Medium Power
    $models.medium_power = @(
        ".\Tools\models\medium-power\gemma-2-2b-it-Q4_K_M.gguf",
        ".\Tools\models\medium-power\gemma-3-4b-it-q4_k_m.gguf",
        ".\Tools\models\medium-power\phi-2.Q4_K_M.gguf",
        ".\Tools\models\medium-power\phi-4-mini-instruct-q4_k_m.gguf",
        ".\Tools\models\medium-power\qwen3-4b-q4_k_m.gguf",
        ".\Tools\models\medium-power\smollm3-3b-q4_k_m.gguf"
    )
    
    # Specialized (get all files from specialized directory)
    $specializedPath = ".\Tools\models\specialized"
    if (Test-Path $specializedPath) {
        $models.specialized = Get-ChildItem -Path $specializedPath -Filter "*.gguf" | Select-Object -ExpandProperty FullName
    } else {
        $models.specialized = @()
    }
    
    return $models
}

function Test-SingleModel {
    param(
        [string]$ModelPath,
        [string]$Category,
        [string]$TestPrompt = "Hello, how are you?"
    )
    
    $modelTestResult = @{
        ModelPath = $ModelPath
        Category = $Category
        ModelName = Split-Path $ModelPath -Leaf
        TestTime = Get-Date
        Success = $false
        Error = $null
        LoadTime = $null
        GenerationTime = $null
        TokensPerSecond = $null
        MemoryUsage = $null
        ResponseLength = $null
    }
    
    try {
        Write-Log "Testing model: $(Split-Path $ModelPath -Leaf)" -Level "INFO"
        
        if (-not (Test-Path $ModelPath)) {
            throw "Model file not found: $ModelPath"
        }
        
        # Test 1: Basic model loading
        $loadStartTime = Get-Date
        $loadArgs = @(
            "-m", $ModelPath,
            "-n", "1",
            "--log-disable",
            "--quiet"
        )
        
        $loadProcess = Start-Process -FilePath $MainBinary -ArgumentList $loadArgs -NoNewWindow -PassThru -Wait
        $loadEndTime = Get-Date
        $modelTestResult.LoadTime = ($loadEndTime - $loadStartTime).TotalSeconds
        
        if ($loadProcess.ExitCode -ne 0) {
            throw "Model loading failed with exit code: $($loadProcess.ExitCode)"
        }
        
        # Test 2: Text generation
        $genStartTime = Get-Date
        $genArgs = @(
            "-m", $ModelPath,
            "-p", $TestPrompt,
            "-n", $MaxTokens,
            "--log-disable",
            "-t", "1",
            "--ctx-size", "2048"
        )
        
        $genProcess = Start-Process -FilePath $MainBinary -ArgumentList $genArgs -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$($env:TEMP)\model_test_output_$(Get-Random).txt"
        $genEndTime = Get-Date
        $modelTestResult.GenerationTime = ($genEndTime - $genStartTime).TotalSeconds
        
        if ($genProcess.ExitCode -ne 0) {
            throw "Text generation failed with exit code: $($genProcess.ExitCode)"
        }
        
        # Calculate performance metrics
        $outputFile = "$($env:TEMP)\model_test_output_$(Get-Random).txt"
        if (Test-Path $outputFile) {
            $output = Get-Content $outputFile -Raw
            $modelTestResult.ResponseLength = $output.Length
            $modelTestResult.TokensPerSecond = if ($modelTestResult.GenerationTime -gt 0) { 
                [math]::Round($MaxTokens / $modelTestResult.GenerationTime, 2) 
            } else { 0 }
            Remove-Item $outputFile -Force
        }
        
        $modelTestResult.Success = $true
        Write-Log "✓ Model test passed: $(Split-Path $ModelPath -Leaf)" -Level "INFO"
        
    } catch {
        $modelTestResult.Error = $_.Exception.Message
        $modelTestResult.Success = $false
        Write-Log "✗ Model test failed: $(Split-Path $ModelPath -Leaf) - $($_.Exception.Message)" -Level "ERROR"
    }
    
    return $modelTestResult
}

function Test-ModelCategory {
    param(
        [string]$Category,
        [array]$ModelPaths
    )
    
    Write-Log "Testing category: $Category ( $($ModelPaths.Count) models )"
    
    $categoryResults = @()
    $progressCount = 0
    
    foreach ($modelPath in $ModelPaths) {
        $progressCount++
        Write-Progress -Activity "Testing $Category models" -Status "Model $progressCount of $($ModelPaths.Count)" -PercentComplete (($progressCount / $ModelPaths.Count) * 100)
        
        $result = Test-SingleModel -ModelPath $modelPath -Category $Category
        $categoryResults += $result
        
        if ($result.Success) {
            $SuccessfulModels += $result
        } else {
            $FailedModels += $result
        }
        
        $TestResults += $result
        
        # Brief pause to prevent system overload
        Start-Sleep -Milliseconds 500
    }
    
    Write-Progress -Activity "Testing $Category models" -Completed
    return $categoryResults
}

function Generate-TestReport {
    param([array]$Results)
    
    $reportPath = ".\Scripts\Logs\Model_Test_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
    
    $reportContent = @"
# Model Test Report

**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Total Models Tested**: $($Results.Count)
**Successful**: $($SuccessfulModels.Count)
**Failed**: $($FailedModels.Count)
**Success Rate**: $([math]::Round(($SuccessfulModels.Count / $Results.Count) * 100, 2))%

## Summary by Category

"@
    
    # Group results by category
    $groupedResults = $Results | Group-Object Category
    
    foreach ($group in $groupedResults) {
        $categorySuccess = ($group.Group | Where-Object { $_.Success }).Count
        $categoryTotal = $group.Group.Count
        $categoryRate = [math]::Round(($categorySuccess / $categoryTotal) * 100, 2)
        
        $reportContent += @"
### $($group.Name)
- Total: $categoryTotal
- Successful: $categorySuccess
- Failed: $($categoryTotal - $categorySuccess)
- Success Rate: $categoryRate%

"@
    }
    
    $reportContent += @"

## Failed Models

"@
    
    if ($FailedModels.Count -gt 0) {
        foreach ($failed in $FailedModels) {
            $reportContent += @"
### $($failed.ModelName)
- **Category**: $($failed.Category)
- **Path**: $($failed.ModelPath)
- **Error**: $($failed.Error)

"@
        }
    } else {
        $reportContent += "✅ All models passed successfully!\n"
    }
    
    $reportContent += @"

## Performance Metrics

"@
    
    $successfulResults = $Results | Where-Object { $_.Success }
    if ($successfulResults.Count -gt 0) {
        $avgLoadTime = [math]::Round(($successfulResults | Measure-Object -Property LoadTime -Average).Average, 2)
        $avgGenTime = [math]::Round(($successfulResults | Measure-Object -Property GenerationTime -Average).Average, 2)
        $avgTPS = [math]::Round(($successfulResults | Measure-Object -Property TokensPerSecond -Average).Average, 2)
        
        $reportContent += @"
- **Average Load Time**: $avgLoadTime seconds
- **Average Generation Time**: $avgGenTime seconds
- **Average Tokens/Second**: $avgTPS
- **Fastest Model**: $($successfulResults | Sort-Object TokensPerSecond -Descending | Select-Object -First 1 | Select-Object -ExpandProperty ModelName) ($($successfulResults | Sort-Object TokensPerSecond -Descending | Select-Object -First 1 | Select-Object -ExpandProperty TokensPerSecond) t/s)
- **Slowest Model**: $($successfulResults | Sort-Object TokensPerSecond | Select-Object -First 1 | Select-Object -ExpandProperty ModelName) ($($successfulResults | Sort-Object TokensPerSecond | Select-Object -First 1 | Select-Object -ExpandProperty TokensPerSecond) t/s)

"@
    }
    
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Log "Test report generated: $reportPath"
    
    return $reportPath
}

# Main execution
try {
    Write-Log "Starting comprehensive model testing framework"
    Write-Log "Parameters: Category=$TestCategory, MaxTokens=$MaxTokens, Timeout=$TimeoutSeconds"
    
    # Check prerequisites
    Test-BinaryAvailability
    
    # Get all models
    $allModels = Get-ModelCategories
    
    if ($TestCategory -eq "all") {
        # Test all categories
        foreach ($category in $allModels.GetEnumerator()) {
            if ($category.Value.Count -gt 0) {
                Test-ModelCategory -Category $category.Name -ModelPaths $category.Value
            }
        }
    } else {
        # Test specific category
        if ($allModels.ContainsKey($TestCategory)) {
            Test-ModelCategory -Category $TestCategory -ModelPaths $allModels[$TestCategory]
        } else {
            throw "Invalid category: $TestCategory"
        }
    }
    
    # Generate report
    if ($GenerateReport -or $TestCategory -eq "all") {
        $reportPath = Generate-TestReport -Results $TestResults
        Write-Host "📊 Test report generated: $reportPath" -ForegroundColor Cyan
    }
    
    # Final summary
    Write-Host "`n🎯 Model Testing Complete!" -ForegroundColor Green
    Write-Host "📈 Total Models Tested: $($TestResults.Count)" -ForegroundColor White
    Write-Host "✅ Successful: $($SuccessfulModels.Count)" -ForegroundColor Green
    Write-Host "❌ Failed: $($FailedModels.Count)" -ForegroundColor Red
    Write-Host "📊 Success Rate: $([math]::Round(($SuccessfulModels.Count / $TestResults.Count) * 100, 2))%" -ForegroundColor Cyan
    
    if ($FailedModels.Count -gt 0) {
        Write-Host "`n⚠️  Failed Models:" -ForegroundColor Yellow
        foreach ($failed in $FailedModels) {
            Write-Host "   ❌ $($failed.ModelName) - $($failed.Error)" -ForegroundColor Red
        }
    }
    
} catch {
    Write-Log "Fatal error in testing framework: $($_.Exception.Message)" -Level "ERROR"
    Write-Host "❌ Testing failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Log "Model testing framework completed successfully"
