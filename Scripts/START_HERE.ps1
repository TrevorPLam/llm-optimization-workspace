# 🚀 **LLM Optimization Workspace - Quick Start Script**
# This script provides easy access to all optimization functions
# Enhanced with 2026 PowerShell best practices and comprehensive validation

# Set strict error handling for robust operation
$ErrorActionPreference = 'Stop'

# Import core module first with validation
try {
    $coreModulePath = ".\llm_optimization_core.ps1"
    if (-not (Test-Path $coreModulePath)) {
        throw "Required core module not found: $coreModulePath"
    }
    
    # Validate core module syntax before loading
    $syntaxErrors = $null
    $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($coreModulePath, [ref]$tokens, [ref]$syntaxErrors)
    
    if ($syntaxErrors.Count -gt 0) {
        throw "Core module has syntax errors: $($syntaxErrors[0].Message)"
    }
    
    . $coreModulePath
    Write-Host "✅ Core module loaded and validated" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to load core module: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please ensure llm_optimization_core.ps1 exists and has valid syntax" -ForegroundColor Yellow
    exit 1
}

#region Comprehensive Script Validation Framework

function Test-ScriptDependencies {
    param([hashtable]$RequiredScripts)
    
    $validationResults = @()
    
    foreach ($script in $RequiredScripts.GetEnumerator()) {
        $result = @{
            ScriptName = $script.Key
            ScriptPath = $script.Value
            Exists = $false
            Loadable = $false
            Error = $null
        }
        
        try {
            # Test file existence
            if (Test-Path $script.Value) {
                $result.Exists = $true
                
                # Test script loading without execution
                $null = [System.Management.Automation.Language.Parser]::ParseFile($script.Value, [ref]$null, [ref]$null)
                $result.Loadable = $true
            }
        } catch {
            $result.Error = $_.Exception.Message
        }
        
        $validationResults += $result
    }
    
    return $validationResults
}

function Get-CurrentModelInventory {
    # Scan Tools/models directory for available models
    $modelsPath = "..\Tools\models"
    $availableModels = @()
    
    if (Test-Path $modelsPath) {
        $availableModels = Get-ChildItem -Path $modelsPath -Filter "*.gguf" | ForEach-Object {
            @{
                Name = $_.Name
                Path = $_.FullName
                Size = [math]::Round($_.Length / 1MB, 2)
                LastModified = $_.LastWriteTime
            }
        }
    }
    
    return $availableModels
}

function Select-BestModelForTask {
    param(
        [string]$TaskType = "general",
        [array]$AvailableModels
    )
    
    if (-not $AvailableModels -or $AvailableModels.Count -eq 0) {
        return $null
    }
    
    # Priority models based on task type and current inventory
    $priorityModels = switch ($TaskType) {
        "general" { @("llama-3.2-1b-instruct-q4_k_m.gguf", "qwen2.5-1.5b-instruct-q4_k_m.gguf", "smolLM2-1.7b-instruct-q4_k_m.gguf") }
        "reasoning" { @("qwen2.5-1.5b-instruct-q4_k_m.gguf", "phi-4-mini-instruct-q4_k_m.gguf", "qwen3-4b-q4_k_m.gguf") }
        "coding" { @("qwen2.5-coder-1.5b-instruct-q4_k_m.gguf", "qwen2.5-1.5b-instruct-q4_k_m.gguf", "llama-3.2-1b-instruct-q4_k_m.gguf") }
        "lightweight" { @("tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf", "llama-3.2-1b-instruct-q4_k_m.gguf") }
        default { @("llama-3.2-1b-instruct-q4_k_m.gguf", "qwen2.5-1.5b-instruct-q4_k_m.gguf") }
    }
    
    # Find first available priority model
    foreach ($priorityModel in $priorityModels) {
        $model = $AvailableModels | Where-Object { $_.Name -eq $priorityModel }
        if ($model) {
            return $model
        }
    }
    
    # Fallback to first available model
    return $AvailableModels[0]
}

function Write-EnhancedError {
    param(
        [string]$Message,
        [string]$Category = "OperationFailed",
        [string]$LogPath = "Logs\menu_errors.log"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - [$Category] $Message"
    
    # Write to console
    Write-Error $Message
    
    # Log to file
    try {
        if (-not (Test-Path (Split-Path $LogPath))) {
            New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null
        }
        Add-Content -Path $LogPath -Value $logEntry
    } catch {
        Write-Warning "Failed to write to log file: $($_.Exception.Message)"
    }
}

#endregion

#region Enhanced Menu System

function Invoke-MenuOption {
    param(
        [string]$Option,
        [string]$ScriptPath,
        [string]$Description,
        [string]$TaskType = "general"
    )
    
    try {
        Write-Host ""
        Write-Host $Description -ForegroundColor Green
        
        # Validate script dependency
        if (-not (Test-Path $ScriptPath)) {
            throw "Required script not found: $ScriptPath"
        }
        
        # Test script syntax before loading
        $syntaxErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$syntaxErrors)
        
        if ($syntaxErrors.Count -gt 0) {
            throw "Script has syntax errors: $($syntaxErrors[0].Message)"
        }
        
        # Load script with error handling
        . $ScriptPath
        
        # Get best model for task
        $availableModels = Get-CurrentModelInventory
        $selectedModel = Select-BestModelForTask -TaskType $TaskType -AvailableModels $availableModels
        
        if (-not $selectedModel) {
            Write-Warning "No models found in Tools/models directory"
            Write-Host "Please ensure you have GGUF model files in the Tools/models directory" -ForegroundColor Yellow
            return
        }
        
        Write-Host "Selected model: $($selectedModel.Name) ($([math]::Round($selectedModel.Size, 2))MB)" -ForegroundColor Cyan
        
        return $selectedModel.Path
        
    } catch {
        Write-EnhancedError -Message "Failed to execute menu option $Option`: $($_.Exception.Message)" -Category "MenuExecution"
        Write-Host "Please check the script and try again." -ForegroundColor Yellow
        return $null
    }
}

#endregion

# Initialize script with comprehensive validation
try {
    Write-Host "🚀 LLM Optimization Workspace - 2026 Edition" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Validate required scripts
    $requiredScripts = @{
        "Core" = ".\llm_optimization_core.ps1"
        "Ultimate Suite" = ".\enhanced_ultimate_suite.ps1"
        "Quantization Suite" = ".\llm_quantization_suite.ps1"
        "Attention Suite" = ".\llm_attention_suite.ps1"
        "Parallel Suite" = ".\llm_parallel_suite.ps1"
        "AVX2 Optimization" = ".\avx2_optimization.ps1"
        "Dashboard" = ".\dashboard.ps1"
    }
    
    $validationResults = Test-ScriptDependencies -RequiredScripts $requiredScripts
    
    $failedScripts = $validationResults | Where-Object { -not $_.Loadable }
    if ($failedScripts.Count -gt 0) {
        Write-Host "⚠️ Some scripts have issues:" -ForegroundColor Yellow
        foreach ($script in $failedScripts) {
            $status = if ($script.Exists) { "Syntax Error" } else { "Missing" }
            Write-Host "  • $($script.ScriptName): $status" -ForegroundColor Gray
            if ($script.Error) {
                Write-Host "    Error: $($script.Error)" -ForegroundColor Red
            }
        }
        Write-Host ""
    }
    
    # Check model inventory
    $availableModels = Get-CurrentModelInventory
    Write-Host "📊 Model Inventory: $($availableModels.Count) models available" -ForegroundColor White
    if ($availableModels.Count -gt 0) {
        $totalSize = [math]::Round(($availableModels | Measure-Object -Property Size -Sum).Sum, 2)
        Write-Host "Total storage: $totalSize MB" -ForegroundColor Gray
    }
    Write-Host ""
    
} catch {
    Write-EnhancedError -Message "Script initialization failed: $($_.Exception.Message)" -Category "Initialization"
    exit 1
}

# Display available options
Write-Host "📋 Available Optimization Options:" -ForegroundColor White
Write-Host ""
Write-Host '1. [STAR] Ultimate Optimization (Recommended)' -ForegroundColor Yellow
Write-Host '2. [MICRO] Quantization Suite (2-bit plus Speculative Decoding)' -ForegroundColor Yellow
Write-Host '3. [EYE] Attention Suite (PagedAttention plus GraphRAG)' -ForegroundColor Yellow
Write-Host '4. [BOLT] Parallel Suite (Continuous Batching plus MoE)' -ForegroundColor Yellow
Write-Host '5. [TOOL] Hardware Optimization (AVX2)' -ForegroundColor Yellow
Write-Host '6. [CHART] Performance Dashboard' -ForegroundColor Yellow
Write-Host '7. [BOOK] Comprehensive Documentation' -ForegroundColor Yellow
Write-Host ""

# Interactive menu
do {
    $choice = Read-Host "Select an option (1-7) or 'q' to quit"
    
    switch ($choice) {
        "1" {
            $modelPath = Invoke-MenuOption -Option "1" -ScriptPath ".\enhanced_ultimate_suite.ps1" -Description "[STAR] Loading Ultimate Optimization Suite..." -TaskType "general"
            
            if ($modelPath) {
                Write-Host "Executing Ultimate Optimization..." -ForegroundColor Yellow
                try {
                    Execute-UltimateOptimization -ModelPath $modelPath -Tokens 200
                } catch {
                    Write-EnhancedError -Message "Ultimate Optimization failed: $($_.Exception.Message)" -Category "Optimization"
                }
            }
        }
        
        "2" {
            $modelPath = Invoke-MenuOption -Option "2" -ScriptPath ".\llm_quantization_suite.ps1" -Description "[MICRO] Loading Quantization Suite..." -TaskType "lightweight"
            
            if ($modelPath) {
                Write-Host "Available Quantization Functions:" -ForegroundColor White
                Write-Host "  • Convert-To2BitQuantization" -ForegroundColor Gray
                Write-Host "  • Start-OptimizedSpeculativeDecoding" -ForegroundColor Gray
                Write-Host "  • Start-QuantizationBenchmark" -ForegroundColor Gray
                Write-Host ""
                
                Write-Host "Running Quantization Benchmark..." -ForegroundColor Yellow
                try {
                    Start-QuantizationBenchmark -Models @($modelPath) -TestTokens 50
                } catch {
                    Write-EnhancedError -Message "Quantization Benchmark failed: $($_.Exception.Message)" -Category "Quantization"
                }
            }
        }
        
        "3" {
            $modelPath = Invoke-MenuOption -Option "3" -ScriptPath ".\llm_attention_suite.ps1" -Description "[EYE] Loading Attention Suite..." -TaskType "reasoning"
            
            if ($modelPath) {
                Write-Host "Available Attention Functions:" -ForegroundColor White
                Write-Host "  • Enable-PagedAttention" -ForegroundColor Gray
                Write-Host "  • Enable-FlashInferCPU" -ForegroundColor Gray
                Write-Host "  • Enable-GraphRAG" -ForegroundColor Gray
                Write-Host "  • Start-AttentionBenchmark" -ForegroundColor Gray
                Write-Host ""
                
                Write-Host "Running Attention Benchmark..." -ForegroundColor Yellow
                try {
                    Start-AttentionBenchmark -ModelPath $modelPath -TestTokens 50
                } catch {
                    Write-EnhancedError -Message "Attention Benchmark failed: $($_.Exception.Message)" -Category "Attention"
                }
            }
        }
        
        "4" {
            $modelPath = Invoke-MenuOption -Option "4" -ScriptPath ".\llm_parallel_suite.ps1" -Description "[BOLT] Loading Parallel Suite..." -TaskType "general"
            
            if ($modelPath) {
                Write-Host "Available Parallel Functions:" -ForegroundColor White
                Write-Host "  • Start-ContinuousBatching" -ForegroundColor Gray
                Write-Host "  • Start-MicroBatching" -ForegroundColor Gray
                Write-Host "  • Enable-CPUExpertParallelism" -ForegroundColor Gray
                Write-Host "  • Start-ParallelBenchmark" -ForegroundColor Gray
                Write-Host ""
                
                Write-Host "Running Parallel Benchmark..." -ForegroundColor Yellow
                try {
                    Start-ParallelBenchmark -ModelPath $modelPath -TestTokens 50
                } catch {
                    Write-EnhancedError -Message "Parallel Benchmark failed: $($_.Exception.Message)" -Category "Parallel"
                }
            }
        }
        
        "5" {
            $modelPath = Invoke-MenuOption -Option "5" -ScriptPath ".\avx2_optimization.ps1" -Description "[TOOL] Loading Hardware Optimization..." -TaskType "lightweight"
            
            if ($modelPath) {
                Write-Host "Testing AVX2 Support..." -ForegroundColor Yellow
                try {
                    Test-AVX2Support
                    
                    Write-Host "Running AVX2 Benchmark..." -ForegroundColor Yellow
                    Start-AVX2Benchmark -ModelPath $modelPath -Tokens 50
                } catch {
                    Write-EnhancedError -Message "AVX2 Optimization failed: $($_.Exception.Message)" -Category "Hardware"
                }
            }
        }
        
        "6" {
            $dashboardPath = Invoke-MenuOption -Option "6" -ScriptPath ".\dashboard.ps1" -Description "[CHART] Launching Performance Dashboard..." -TaskType "general"
            
            if ($dashboardPath) {
                Write-Host "Dashboard loaded successfully" -ForegroundColor Green
            }
        }
        
        "7" {
            Write-Host ""
            Write-Host "[BOOK] Opening Documentation..." -ForegroundColor Green
            Write-Host ""
            Write-Host "Available Documentation:" -ForegroundColor White
            Write-Host "  • README.md - Complete workspace guide" -ForegroundColor Gray
            Write-Host "  • Documentation/Research.md - Master reference" -ForegroundColor Gray
            Write-Host "  • Documentation/llm_optimization_guide.md - 2026 research guide" -ForegroundColor Gray
            Write-Host ""
            
            $readmePath = "..\README.md"
            if (Test-Path $readmePath) {
                Write-Host "Opening README.md..." -ForegroundColor Yellow
                try {
                    Start-Process $readmePath
                } catch {
                    Write-EnhancedError -Message "Failed to open documentation: $($_.Exception.Message)" -Category "Documentation"
                }
            } else {
                Write-Warning "README.md not found at: $readmePath"
                Write-Host "Please check the documentation directory" -ForegroundColor Yellow
            }
        }
        
        "q" {
            Write-Host ""
            Write-Host "👋 Thank you for using LLM Optimization Workspace!" -ForegroundColor Green
            Write-Host "🌟 Your consumer hardware now delivers enterprise-grade performance!" -ForegroundColor Cyan
            break
        }
        
        default {
            Write-Host ""
            Write-Host "❌ Invalid option. Please select 1-7 or 'q' to quit." -ForegroundColor Red
        }
    }
    
    if ($choice -ne 'q') {
        Write-Host ""
        Write-Host "Press Enter to continue..."
        Read-Host
        Write-Host ""
        Write-Host "🚀 LLM Optimization Workspace - 2026 Edition" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "📋 Available Optimization Options:" -ForegroundColor White
        Write-Host ""
        Write-Host '1. [STAR] Ultimate Optimization (Recommended)' -ForegroundColor Yellow
        Write-Host '2. [MICRO] Quantization Suite (2-bit plus Speculative Decoding)' -ForegroundColor Yellow
        Write-Host '3. [EYE] Attention Suite (PagedAttention plus GraphRAG)' -ForegroundColor Yellow
        Write-Host '4. [BOLT] Parallel Suite (Continuous Batching plus MoE)' -ForegroundColor Yellow
        Write-Host '5. [TOOL] Hardware Optimization (AVX2)' -ForegroundColor Yellow
        Write-Host '6. [CHART] Performance Dashboard' -ForegroundColor Yellow
        Write-Host '7. [BOOK] Comprehensive Documentation' -ForegroundColor Yellow
        Write-Host ""
    }
} while ($choice -ne 'q')
