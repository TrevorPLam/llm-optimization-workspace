@echo off
REM llama.cpp Environment Configuration Script
REM Equivalent to Ollama environment variables for i5-9500 optimization

echo Setting up llama.cpp environment variables...

REM CPU Optimization (equivalent to OLLAMA_NUM_PARALLEL)
set LLAMACPP_NUM_PARALLEL=1
set LLAMACPP_THREADS=6
set LLAMACPP_CPU_AFFINITY=0x3F

REM Memory Management (equivalent to OLLAMA_MAX_LOADED_MODELS)
set LLAMACPP_MAX_LOADED_MODELS=1
set LLAMACPP_MEMORY_LIMIT_GB=50

REM KV Cache Optimization (equivalent to OLLAMA_KV_CACHE_TYPE)
set LLAMACPP_KV_CACHE_TYPE=q8_0
set LLAMACPP_FLASH_ATTENTION=1

REM Context and Batch Size
set LLAMACPP_CTX_SIZE=2048
set LLAMACPP_BATCH_SIZE=512
set LLAMACPP_MICRO_BATCH_SIZE=32

REM Model Path Configuration
set LLAMACPP_MODELS_PATH=%~dp0Tools\models

REM Server Configuration
set LLAMACPP_HOST=127.0.0.1
set LLAMACPP_PORT=8080

echo Environment variables set:
echo - LLAMACPP_NUM_PARALLEL: %LLAMACPP_NUM_PARALLEL%
echo - LLAMACPP_THREADS: %LLAMACPP_THREADS%
echo - LLAMACPP_KV_CACHE_TYPE: %LLAMACPP_KV_CACHE_TYPE%
echo - LLAMACPP_FLASH_ATTENTION: %LLAMACPP_FLASH_ATTENTION%
echo - LLAMACPP_CTX_SIZE: %LLAMACPP_CTX_SIZE%
echo - LLAMACPP_MODELS_PATH: %LLAMACPP_MODELS_PATH%
echo.
echo Configuration complete!
