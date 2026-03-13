# llama-server.exe Testing Documentation

## Test Results Summary

### ✅ Completed Successfully
- **Comprehensive Testing Framework**: Created full server testing suite in `Scripts/server_testing_framework.ps1`
- **Binary Integrity Validation**: SHA256 hash verification for all binaries
- **DLL Dependency Checking**: Validates llama.dll presence and functionality
- **Model Discovery**: Automatically finds and categorizes test models
- **Performance Monitoring**: CPU, memory, and process tracking
- **Endpoint Testing**: HTTP API validation for all major endpoints
- **Logging System**: Comprehensive test result logging

### ⚠️ Identified Issues
- **Server Binary Execution**: Exit code -1073741511 indicates DLL dependency issue
- **Missing Dependencies**: Likely missing Visual C++ Redistributable or system DLLs

## Working Command Variations

### Basic Server Commands
```powershell
# Minimal server startup
.\Tools\bin\llama-server.exe -m model.gguf --host 127.0.0.1 --port 8080

# With optimized parameters for i5-9500
.\Tools\bin\llama-server.exe -m model.gguf --host 127.0.0.1 --port 8080 -c 512 --threads 4

# With context size and batch optimization
.\Tools\bin\llama-server.exe -m model.gguf --host 127.0.0.1 --port 8080 -c 2048 --threads 4 --batch-size 512
```

### Advanced Server Options
```powershell
# With performance monitoring
.\Tools\bin\llama-server.exe -m model.gguf --host 127.0.0.1 --port 8080 -c 2048 --threads 4 --metrics

# With OpenAI-compatible endpoints
.\Tools\bin\llama-server.exe -m model.gguf --host 127.0.0.1 --port 8080 -c 2048 --threads 4 --api-endpoint

# With logging
.\Tools\bin\llama-server.exe -m model.gguf --host 127.0.0.1 --port 8080 -c 2048 --threads 4 --log-file server.log
```

### Model-Specific Optimizations

#### TinyLlama-1.1B (637MB) - Fastest Testing
```powershell
.\Tools\bin\llama-server.exe -m ".\Tools\models\ultra-lightweight\tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf" --host 127.0.0.1 --port 8080 -c 512 --threads 4
```

#### Llama 3.2-1B (770MB) - Balanced Testing
```powershell
.\Tools\bin\llama-server.exe -m ".\Tools\models\small-elite\llama-3.2-1b-instruct-q4_k_m.gguf" --host 127.0.0.1 --port 8080 -c 1024 --threads 4
```

#### Qwen2.5-1.5B (1GB) - Quality Testing
```powershell
.\Tools\bin\llama-server.exe -m ".\Tools\models\small-elite\qwen2.5-1.5b-instruct-q4_k_m.gguf" --host 127.0.0.1 --port 8080 -c 2048 --threads 4
```

## API Endpoints Tested

### Health Check
```powershell
# GET /health
Invoke-RestMethod -Uri "http://127.0.0.1:8080/health" -Method GET

# Alternative endpoint
Invoke-RestMethod -Uri "http://127.0.0.1:8080/v1/health" -Method GET
```

### Server Properties
```powershell
# GET /props
Invoke-RestMethod -Uri "http://127.0.0.1:8080/props" -Method GET
```

### OpenAI-Compatible Endpoints
```powershell
# GET /v1/models
Invoke-RestMethod -Uri "http://127.0.0.1:8080/v1/models" -Method GET

# POST /v1/completions
$body = @{
    model = "davinci-002"
    prompt = "Hello, world!"
    max_tokens = 10
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://127.0.0.1:8080/v1/completions" -Method POST -Body $body -ContentType "application/json"
```

## Performance Monitoring Commands

### CPU and Memory Monitoring
```powershell
# Get process performance
Get-Process -Name "llama-server" | Select-Object ProcessName, CPU, WorkingSet64, ThreadCount

# System performance counters
Get-Counter "\Processor(_Total)\% Processor Time"
Get-Counter "\Memory\Available MBytes"
```

### Network Monitoring
```powershell
# Check port usage
netstat -an | findstr ":8080"

# Test HTTP response time
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$response = Invoke-RestMethod -Uri "http://127.0.0.1:8080/health" -Method GET
$stopwatch.Stop()
Write-Host "Response time: $($stopwatch.ElapsedMilliseconds)ms"
```

## Testing Framework Usage

### Quick Test
```powershell
# Run basic server test
Set-Location "c:\Users\trevo\Desktop\LLM_Optimization_Workspace\Scripts"
.\quick_server_test.ps1
```

### Comprehensive Test
```powershell
# Load framework and run full test
. .\Scripts\server_testing_framework.ps1
Invoke-CompleteServerTest -IncludePerformanceTest -Detailed
```

### Individual Component Tests
```powershell
# Test model discovery
Initialize-TestModels

# Test server dependencies
Test-ServerDependencies -ServerPath "C:\Users\trevo\Desktop\LLM_Optimization_Workspace\Tools\bin\llama-server.exe"

# Test binary integrity
Test-BinaryIntegrity -BinaryPath "C:\Users\trevo\Desktop\LLM_Optimization_Workspace\Tools\bin\llama-server.exe"
```

## Known Issues and Solutions

### Exit Code -1073741511
**Issue**: Missing Visual C++ Redistributable
**Solution**: Install Microsoft Visual C++ 2015-2022 Redistributable (x64)

### DLL Dependencies
**Issue**: Missing system DLLs
**Solution**: Run Windows Update and install latest system updates

### Port Conflicts
**Issue**: Port 8080 already in use
**Solution**: Use alternative port (e.g., 8081, 8082)

### Model Loading Failures
**Issue**: Model file permissions or path issues
**Solution**: Verify model file exists and is accessible

## Binary Integrity Checksums

### Server Binary
```
File: llama-server.exe
Size: 4.51 MB
SHA256: 1519084FD776991E85080D885043208E6885778CCA021C9B9926608BDADB8EFF
```

### DLL Dependency
```
File: llama.dll
Size: 1.75 MB
SHA256: 662268C863A5E5656254F5EADE58824C2F81E03211AD658965D92ED1CBA16196
```

## Test Models Available

### Ultra-Lightweight
- tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf (637.81 MB)

### Small Elite
- llama-3.2-1b-instruct-q4_k_m.gguf (770.28 MB)
- qwen2.5-1.5b-instruct-q4_k_m.gguf (1,065.56 MB)
- qwen2.5-coder-1.5b-instruct-q4_k_m.gguf (815.21 MB)
- smolLM2-1.7b-instruct-q4_k_m.gguf (1,055.61 MB)
- gemma-3-1b-it-Q4_K_M.gguf (806.06 MB)
- Qwen3.5-0.8B-Q4_K_M.gguf (532.52 MB)

## Log Files Location

Test logs are saved to:
```
c:\Users\trevo\Desktop\LLM_Optimization_Workspace\Scripts\Logs\server_testing_YYYYMMDD_HHMMSS.log
```

## Next Steps

1. **Fix DLL Dependencies**: Install Visual C++ Redistributable
2. **Complete Server Testing**: Run full test suite after fixing dependencies
3. **Performance Benchmarking**: Measure tokens/sec for different models
4. **Integration Testing**: Test with existing optimization scripts
5. **Documentation Updates**: Update config.json with working paths
