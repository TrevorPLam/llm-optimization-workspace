# Scripts Overview

This folder contains the full PowerShell suite for the LLM Optimization Workspace. Each script targets a specific optimization domain for Intel i5-9500 Coffee Lake hardware. Use this document to understand when to run each script and the prerequisites involved.

## Quick Navigation

| Script | Purpose | Key Entry Points |
|--------|---------|------------------|
| `START_HERE.ps1` | Interactive launcher covering all suites | Menu options 1-7 for Ultimate, Quantization, Attention, Parallel, Hardware, Dashboard, Docs |
| `llm_optimization_core.ps1` | Shared library with hardware tuning, logging, config helpers, performance utilities | Imported by other scripts; exports Coffee Lake affinity tools, config loaders, logging |
| `enhanced_ultimate_suite.ps1` | Full-stack orchestrator combining system tuning, quantization, speculative decoding, attention optimizations, and llama-server launch | `Execute-UltimateOptimization`, `Invoke-UltimateLLMOptimization` |
| `ultimate_cpu_infrastructure.ps1` | System-level hardening (power plans, large pages, VA space, process priority) | `Optimize-UltimatePerformance`, `Set-CoffeeLakeProcessOptimization` |
| `llm_quantization_suite.ps1` | ParetoQ-inspired quantization, KV cache compression, speculative decoding setup | `Convert-To2BitQuantization`, `Enable-KVCacheQuantization`, `Start-QuantizationBenchmark` |
| `llm_attention_suite.ps1` | PagedAttention, FlashInfer CPU, GraphRAG simulations, cache monitoring | `Enable-PagedAttention`, `Enable-FlashInferCPU`, `Enable-GraphRAG`, `Start-AttentionBenchmark` |
| `llm_parallel_suite.ps1` | Continuous batching, micro/macro scheduling, CPU Mixture-of-Experts demos | `Start-ContinuousBatching`, `Start-MicroBatching`, `Enable-CPUExpertParallelism`, `Start-ParallelBenchmark` |
| `avx2_optimization.ps1` | AVX2 capability checks and benchmarks | `Test-AVX2Support`, `Start-AVX2Benchmark` |
| `dashboard.ps1` | Real-time performance dashboard and logging aggregation | `Start-PerformanceDashboard` |

## Usage Patterns

1. **New setup**: Run `START_HERE.ps1` and choose option 1 (Ultimate Optimization) after ensuring a model exists under `Tools/models`.
2. **Quantization experiments**: Source `llm_quantization_suite.ps1` in PowerShell, then call the conversion or benchmark functions with desired models.
3. **Attention research**: Use `llm_attention_suite.ps1` functions to toggle PagedAttention or FlashInfer CPU modes, optionally piping results into the dashboard script.
4. **Parallel experimentation**: Execute `Start-ContinuousBatching` to simulate continuous batching/micro-batching scenarios; combine with dashboard for monitoring.
5. **System tuning**: Apply `Optimize-UltimatePerformance` from `ultimate_cpu_infrastructure.ps1` before long-running inference sessions.

## Prerequisites

- Import the core module when invoking scripts directly:
  ```powershell
  Import-Module .\Scripts\llm_optimization_core.ps1
  ```
- Ensure binaries referenced in `config.json` exist (e.g., `.\Tools\bin\main.exe`).
- Verify models are present in `Tools/models` (Q4_K_M quantizations recommended for i5-9500).

## Notes

- Many functions simulate benchmarks if hardware/resources are unavailable; logs will indicate "Simulation" where applicable.
- Scripts assume execution from repository root; adjust relative paths if running elsewhere.
- For custom configurations, edit `config.json` or pass explicit parameters to functions (`-ModelPath`, `-Tokens`, etc.).
