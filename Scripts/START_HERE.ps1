# 🚀 **LLM Optimization Workspace - Quick Start Script**
# This script provides easy access to all optimization functions

# Import core module first
. .\llm_optimization_core.ps1

Write-Host "🚀 LLM Optimization Workspace - 2026 Edition" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Display available options
Write-Host "📋 Available Optimization Options:" -ForegroundColor White
Write-Host ""
Write-Host "1. 🎯 Ultimate Optimization (Recommended)" -ForegroundColor Yellow
Write-Host "2. 🔬 Quantization Suite (2-bit + Speculative Decoding)" -ForegroundColor Yellow
Write-Host "3. 👁️ Attention Suite (PagedAttention + GraphRAG)" -ForegroundColor Yellow
Write-Host "4. ⚡ Parallel Suite (Continuous Batching + MoE)" -ForegroundColor Yellow
Write-Host "5. 🔧 Hardware Optimization (AVX2)" -ForegroundColor Yellow
Write-Host "6. 📊 Performance Dashboard" -ForegroundColor Yellow
Write-Host "7. 📚 Comprehensive Documentation" -ForegroundColor Yellow
Write-Host ""

# Interactive menu
do {
    $choice = Read-Host "Select an option (1-7) or 'q' to quit"
    
    switch ($choice) {
        "1" {
            Write-Host ""
            Write-Host "🎯 Loading Ultimate Optimization Suite..." -ForegroundColor Green
            . .\enhanced_ultimate_suite.ps1
            
            $modelPath = "..\Tools\models\tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
            if (Test-Path $modelPath) {
                Write-Host "Executing Ultimate Optimization..." -ForegroundColor Yellow
                Execute-UltimateOptimization -ModelPath $modelPath -Tokens 200
            } else {
                Write-Host "❌ Model not found: $modelPath" -ForegroundColor Red
                Write-Host "Please ensure your models are in the Tools/models directory" -ForegroundColor Gray
            }
        }
        
        "2" {
            Write-Host ""
            Write-Host "🔬 Loading Quantization Suite..." -ForegroundColor Green
            . .\llm_quantization_suite.ps1
            
            Write-Host "Available Quantization Functions:" -ForegroundColor White
            Write-Host "  • Convert-To2BitQuantization" -ForegroundColor Gray
            Write-Host "  • Start-OptimizedSpeculativeDecoding" -ForegroundColor Gray
            Write-Host "  • Start-QuantizationBenchmark" -ForegroundColor Gray
            Write-Host ""
            
            $modelPath = "..\Tools\models\tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
            if (Test-Path $modelPath) {
                Write-Host "Running Quantization Benchmark..." -ForegroundColor Yellow
                Start-QuantizationBenchmark -Models @($modelPath) -TestTokens 50
            } else {
                Write-Host "❌ Model not found: $modelPath" -ForegroundColor Red
            }
        }
        
        "3" {
            Write-Host ""
            Write-Host "👁️ Loading Attention Suite..." -ForegroundColor Green
            . .\llm_attention_suite.ps1
            
            Write-Host "Available Attention Functions:" -ForegroundColor White
            Write-Host "  • Enable-PagedAttention" -ForegroundColor Gray
            Write-Host "  • Enable-FlashInferCPU" -ForegroundColor Gray
            Write-Host "  • Enable-GraphRAG" -ForegroundColor Gray
            Write-Host "  • Start-AttentionBenchmark" -ForegroundColor Gray
            Write-Host ""
            
            $modelPath = "..\Tools\models\tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
            if (Test-Path $modelPath) {
                Write-Host "Running Attention Benchmark..." -ForegroundColor Yellow
                Start-AttentionBenchmark -ModelPath $modelPath -TestTokens 50
            } else {
                Write-Host "❌ Model not found: $modelPath" -ForegroundColor Red
            }
        }
        
        "4" {
            Write-Host ""
            Write-Host "⚡ Loading Parallel Suite..." -ForegroundColor Green
            . .\llm_parallel_suite.ps1
            
            Write-Host "Available Parallel Functions:" -ForegroundColor White
            Write-Host "  • Start-ContinuousBatching" -ForegroundColor Gray
            Write-Host "  • Start-MicroBatching" -ForegroundColor Gray
            Write-Host "  • Enable-CPUExpertParallelism" -ForegroundColor Gray
            Write-Host "  • Start-ParallelBenchmark" -ForegroundColor Gray
            Write-Host ""
            
            $modelPath = "..\Tools\models\tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
            if (Test-Path $modelPath) {
                Write-Host "Running Parallel Benchmark..." -ForegroundColor Yellow
                Start-ParallelBenchmark -ModelPath $modelPath -TestTokens 50
            } else {
                Write-Host "❌ Model not found: $modelPath" -ForegroundColor Red
            }
        }
        
        "5" {
            Write-Host ""
            Write-Host "🔧 Loading Hardware Optimization..." -ForegroundColor Green
            . .\avx2_optimization.ps1
            
            Write-Host "Testing AVX2 Support..." -ForegroundColor Yellow
            Test-AVX2Support
            
            $modelPath = "..\Tools\models\tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
            if (Test-Path $modelPath) {
                Write-Host "Running AVX2 Benchmark..." -ForegroundColor Yellow
                Start-AVX2Benchmark -ModelPath $modelPath -Tokens 50
            } else {
                Write-Host "❌ Model not found: $modelPath" -ForegroundColor Red
            }
        }
        
        "6" {
            Write-Host ""
            Write-Host "📊 Launching Performance Dashboard..." -ForegroundColor Green
            . .\dashboard.ps1
        }
        
        "7" {
            Write-Host ""
            Write-Host "📚 Opening Documentation..." -ForegroundColor Green
            Write-Host ""
            Write-Host "Available Documentation:" -ForegroundColor White
            Write-Host "  • README.md - Complete workspace guide" -ForegroundColor Gray
            Write-Host "  • Documentation/Research.md - Master reference" -ForegroundColor Gray
            Write-Host "  • Documentation/llm_optimization_guide.md - 2026 research guide" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Opening README.md..." -ForegroundColor Yellow
            Start-Process "..\README.md"
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
    
    if ($choice -ne "q") {
        Write-Host ""
        Write-Host "Press Enter to continue..."
        Read-Host
        Write-Host ""
        Write-Host "🚀 LLM Optimization Workspace - 2026 Edition" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "📋 Available Optimization Options:" -ForegroundColor White
        Write-Host ""
        Write-Host "1. 🎯 Ultimate Optimization (Recommended)" -ForegroundColor Yellow
        Write-Host "2. 🔬 Quantization Suite (2-bit + Speculative Decoding)" -ForegroundColor Yellow
        Write-Host "3. 👁️ Attention Suite (PagedAttention + GraphRAG)" -ForegroundColor Yellow
        Write-Host "4. ⚡ Parallel Suite (Continuous Batching + MoE)" -ForegroundColor Yellow
        Write-Host "5. 🔧 Hardware Optimization (AVX2)" -ForegroundColor Yellow
        Write-Host "6. 📊 Performance Dashboard" -ForegroundColor Yellow
        Write-Host "7. 📚 Comprehensive Documentation" -ForegroundColor Yellow
        Write-Host ""
    }
} while ($choice -ne "q")
