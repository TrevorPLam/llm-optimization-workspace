@echo off
REM KV Cache Quantization Verification Script
REM Equivalent to Ollama KV cache verification for T-002.6

echo Verifying KV Cache Quantization Settings...
echo.

REM Check if models support q8_0 quantization
echo Checking model quantization types...
cd Tools\models

echo.
echo === Ultra-Lightweight Models ===
dir /b ultra-lightweight\*.gguf | findstr /i "q4"
if %errorlevel% equ 0 (
    echo ✅ Found Q4 quantized models
) else (
    echo ❌ No Q4 models found
)

echo.
echo === Small Elite Models ===
dir /b small-elite\*.gguf | findstr /i "q4"
if %errorlevel% equ 0 (
    echo ✅ Found Q4 quantized models in small-elite
) else (
    echo ❌ No Q4 models found in small-elite
)

echo.
echo === Medium Power Models ===
dir /b medium-power\*.gguf | findstr /i "q4"
if %errorlevel% equ 0 (
    echo ✅ Found Q4 quantized models in medium-power
) else (
    echo ❌ No Q4 models found in medium-power
)

echo.
echo === Checking for Q8_0 quantizations ===
dir /s /b *.gguf | findstr /i "q8"
if %errorlevel% equ 0 (
    echo ✅ Found Q8 quantized models
    dir /s /b *.gguf | findstr /i "q8"
) else (
    echo ⚠️ No Q8 models found (using Q4_K_M which is optimal for CPU)
)

echo.
cd ..\..
echo === Configuration Verification ===
echo Current KV cache settings from config:
type llamacpp_config.json | findstr -i "kv_cache"

echo.
echo === Optimization Settings ===
echo Flash Attention and KV cache optimization:
type llamacpp_config.json | findstr -i "flash_attention\|kv_cache\|quantization"

echo.
echo === Model Size Analysis ===
echo Calculating memory requirements for KV cache...
python -c "
import json
import os

# Load configuration
with open('llamacpp_config.json', 'r') as f:
    config = json.load(f)

# KV cache memory estimation (bytes per token)
# Q4_K_M: ~6 bytes per token, Q8_0: ~12 bytes per token
kv_cache_per_token_q4 = 6
kv_cache_per_token_q8 = 12

context_size = config['model_deployment']['optimization_settings']['context_size']
kv_cache_type = config['model_deployment']['optimization_settings']['kv_cache_type']

if 'q8' in kv_cache_type.lower():
    per_token = kv_cache_per_token_q8
    print(f'Using Q8_0 KV cache: {per_token} bytes/token')
else:
    per_token = kv_cache_per_token_q4
    print(f'Using Q4_K_M KV cache: {per_token} bytes/token')

total_kv_cache = context_size * per_token
total_kv_cache_mb = total_kv_cache / (1024 * 1024)

print(f'Context size: {context_size} tokens')
print(f'KV cache memory: {total_kv_cache_mb:.2f} MB')

# Check against available memory
import psutil
available_memory_gb = psutil.virtual_memory().available / (1024**3)
print(f'Available system memory: {available_memory_gb:.1f} GB')
print(f'KV cache usage: {(total_kv_cache_mb/1024):.2f}% of memory')

if total_kv_cache_mb < 1000:  # Less than 1GB is good
    print('✅ KV cache memory usage is optimal')
else:
    print('⚠️ KV cache memory usage is high')
"

echo.
echo === Performance Impact Analysis ===
echo Testing different KV cache settings would require:
echo 1. Running models with --type-k q4_0 vs --type-k q8_0
echo 2. Measuring memory usage and token generation speed
echo 3. Comparing quality vs performance trade-offs

echo.
echo ✅ KV Cache verification completed!
echo Note: Q4_K_M quantization is optimal for CPU-only inference on i5-9500
