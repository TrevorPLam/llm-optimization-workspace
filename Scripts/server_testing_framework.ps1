# LLM Server Testing Framework
# Comprehensive llama-server.exe testing and validation suite
# Based on 2026 llama.cpp server API and PowerShell best practices

#Requires -Version 5.1

#region Module Configuration

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Module variables
$script:LogFile = "Logs\server_testing_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:TestResults = @()
$script:ServerProcess = $null
$script:TestModels = @()
$script:ValidationCache = @{}

#endregion

#region Logging Framework

function Write-ServerTestLog {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Test')]
        [string]$Level,
        
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Component = "ServerTest",
        
        [Parameter(Mandatory=$false)]
        [switch]$NoTimestamp
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $displayTimestamp = if (-not $NoTimestamp) { "[$timestamp] " } else { "" }
    
    $color = switch ($Level) {
        'Info' { 'White' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
        'Test' { 'Cyan' }
    }
    
    $prefix = switch ($Level) {
        'Info' { 'ℹ️' }
        'Warning' { '⚠️' }
        'Error' { '❌' }
        'Success' { '✅' }
        'Test' { '🧪' }
    }
    
    $messageLine = "${displayTimestamp}${prefix} [$Component] $Message"
    Write-Host $messageLine -ForegroundColor $color
    
    # Ensure log directory exists
    $logDir = Split-Path $script:LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    # Write to log file
    $logLine = "[$timestamp] ${prefix} [$Component] $Message"
    Add-Content -Path $script:LogFile -Value $logLine -ErrorAction SilentlyContinue
}

function Write-TestResult {
    param(
        [Parameter(Mandatory)]
        [string]$TestName,
        
        [Parameter(Mandatory)]
        [bool]$Success,
        
        [Parameter(Mandatory=$false)]
        [string]$Details = "",
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Metrics = @{},
        
        [Parameter(Mandatory=$false)]
        [string]$Error = ""
    )
    
    $result = @{
        TestName = $TestName
        Success = $Success
        Timestamp = Get-Date
        Details = $Details
        Metrics = $Metrics
        Error = $Error
        Duration = if ($Metrics.ContainsKey('Duration')) { $Metrics.Duration } else { 0 }
    }
    
    $script:TestResults += $result
    
    $status = if ($Success) { "SUCCESS" } else { "FAILED" }
    $statusIcon = if ($Success) { "✅" } else { "❌" }
    
    Write-ServerTestLog -Level Test -Message "$statusIcon $TestName - $status"
    if ($Details) { Write-ServerTestLog -Level Info -Message "   Details: $Details" }
    if ($Error) { Write-ServerTestLog -Level Error -Message "   Error: $Error" }
    if ($Metrics.Count -gt 0) {
        foreach ($metric in $Metrics.GetEnumerator()) {
            Write-ServerTestLog -Level Info -Message "   $($metric.Key): $($metric.Value)"
        }
    }
}

#endregion

#region Binary Integrity Validation

function Test-BinaryIntegrity {
    param(
        [Parameter(Mandatory)]
        [string]$BinaryPath,
        
        [Parameter(Mandatory=$false)]
        [string]$ExpectedHash = ""
    )
    
    Write-ServerTestLog -Level Info -Message "Testing binary integrity: $BinaryPath"
    
    try {
        # Check if binary exists
        if (-not (Test-Path $BinaryPath)) {
            throw "Binary not found: $BinaryPath"
        }
        
        # Get file info
        $fileInfo = Get-Item $BinaryPath
        $fileSize = [math]::Round($fileInfo.Length / 1MB, 2)
        
        # Calculate hash
        Write-ServerTestLog -Level Info -Message "Calculating SHA256 hash..."
        $hashResult = Get-FileHash -Path $BinaryPath -Algorithm SHA256
        $calculatedHash = $hashResult.Hash
        
        $metrics = @{
            FileSize = $fileSize
            CalculatedHash = $calculatedHash
            HashVerificationTime = (Get-Date)
        }
        
        # Verify against expected hash if provided
        if ($ExpectedHash) {
            $hashMatch = $calculatedHash -eq $ExpectedHash
            $metrics.ExpectedHash = $ExpectedHash
            $metrics.HashMatch = $hashMatch
            
            if ($hashMatch) {
                Write-TestResult -TestName "Binary Integrity Check" -Success $true -Details "Hash verified successfully" -Metrics $metrics
                return $true
            } else {
                Write-TestResult -TestName "Binary Integrity Check" -Success $false -Details "Hash mismatch detected" -Error "Expected: $ExpectedHash, Actual: $calculatedHash" -Metrics $metrics
                return $false
            }
        } else {
            Write-TestResult -TestName "Binary Integrity Check" -Success $true -Details "Hash calculated (no expected hash provided)" -Metrics $metrics
            return $true
        }
    }
    catch {
        Write-TestResult -TestName "Binary Integrity Check" -Success $false -Error $_.Exception.Message
        return $false
    }
}

function Test-ServerDependencies {
    param(
        [Parameter(Mandatory)]
        [string]$ServerPath
    )
    
    Write-ServerTestLog -Level Info -Message "Testing server dependencies"
    
    try {
        $result = @{
            Success = $true
            MissingFiles = @()
            DependencyIssues = @()
            TestResults = @()
        }
        
        # Check server binary
        $serverTest = Test-BinaryIntegrity -BinaryPath $ServerPath
        $result.TestResults += @{ Name = "Server Binary"; Success = $serverTest; Path = $ServerPath }
        
        if (-not $serverTest) {
            $result.Success = $false
            $result.MissingFiles += $ServerPath
        }
        
        # Check for llama.dll dependency
        $serverDir = Split-Path $ServerPath -Parent
        $dllPath = Join-Path $serverDir "llama.dll"
        
        if (Test-Path $dllPath) {
            $dllTest = Test-BinaryIntegrity -BinaryPath $dllPath
            $result.TestResults += @{ Name = "llama.dll"; Success = $dllTest; Path = $dllPath }
            
            if (-not $dllTest) {
                $result.Success = $false
                $result.MissingFiles += $dllPath
            }
        } else {
            $result.Success = $false
            $result.MissingFiles += "llama.dll"
            $result.DependencyIssues += "llama.dll not found in server directory"
        }
        
        # Test binary execution (help command) - use absolute path
        Write-ServerTestLog -Level Info -Message "Testing binary execution..."
        try {
            $helpOutput = & $ServerPath --help 2>&1
            if ($LASTEXITCODE -eq 0 -or $helpOutput -like "*usage*" -or $helpOutput -like "*help*") {
                $result.TestResults += @{ Name = "Binary Execution"; Success = $true; Details = "Help command works" }
            } else {
                $result.Success = $false
                $result.DependencyIssues += "Binary execution failed (Exit code: $LASTEXITCODE)"
                $result.TestResults += @{ Name = "Binary Execution"; Success = $false; Details = "Exit code: $LASTEXITCODE" }
            }
        } catch {
            $result.Success = $false
            $result.DependencyIssues += "Binary execution exception: $($_.Exception.Message)"
            $result.TestResults += @{ Name = "Binary Execution"; Success = $false; Details = $_.Exception.Message }
        }
        
        # Log results
        foreach ($testResult in $result.TestResults) {
            $status = if ($testResult.Success) { "✅" } else { "❌" }
            Write-ServerTestLog -Level Info -Message "  $status $($testResult.Name): $($testResult.Details)"
        }
        
        if ($result.Success) {
            Write-TestResult -TestName "Server Dependencies" -Success $true -Details "All dependencies validated"
        } else {
            $errorDetails = $result.DependencyIssues -join "; "
            Write-TestResult -TestName "Server Dependencies" -Success $false -Details "Dependency issues found" -Error $errorDetails
        }
        
        return $result
    }
    catch {
        Write-TestResult -TestName "Server Dependencies" -Success $false -Error $_.Exception.Message
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

#endregion

#region Model Management

function Initialize-TestModels {
    Write-ServerTestLog -Level Info -Message "Initializing test models..."
    
    # Get script directory and build absolute paths
    $scriptDir = Split-Path $PSScriptRoot -Parent
    $modelPaths = @(
        "$scriptDir\Tools\models\ultra-lightweight\tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
        "$scriptDir\Tools\models\small-elite\llama-3.2-1b-instruct-q4_k_m.gguf",
        "$scriptDir\Tools\models\small-elite\qwen2.5-1.5b-instruct-q4_k_m.gguf"
    )
    
    $availableModels = @()
    
    foreach ($modelPath in $modelPaths) {
        if (Test-Path $modelPath) {
            $modelInfo = Get-Item $modelPath
            $modelSize = [math]::Round($modelInfo.Length / 1MB, 2)
            
            $model = @{
                Path = $modelPath
                Name = Split-Path $modelPath -Leaf
                Size = $modelSize
                Exists = $true
            }
            
            $availableModels += $model
            Write-ServerTestLog -Level Info -Message "  ✅ Found: $($model.Name) ($($model.Size)MB)"
        } else {
            Write-ServerTestLog -Level Warning -Message "  ❌ Missing: $modelPath"
        }
    }
    
    $script:TestModels = $availableModels
    
    if ($availableModels.Count -eq 0) {
        Write-TestResult -TestName "Model Discovery" -Success $false -Error "No test models found"
        return $false
    } else {
        Write-TestResult -TestName "Model Discovery" -Success $true -Details "Found $($availableModels.Count) test models"
        return $true
    }
}

function Get-OptimalTestModel {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Preference = "fastest"
    )
    
    if ($script:TestModels.Count -eq 0) {
        return $null
    }
    
    switch ($Preference) {
        "fastest" {
            return $script:TestModels | Sort-Object Size | Select-Object -First 1
        }
        "balanced" {
            return $script:TestModels | Sort-Object Size | Select-Object -Skip 1 -First 1
        }
        "largest" {
            return $script:TestModels | Sort-Object Size -Descending | Select-Object -First 1
        }
        default {
            return $script:TestModels | Select-Object -First 1
        }
    }
}

#endregion

#region Server Process Management

function Start-TestServer {
    param(
        [Parameter(Mandatory)]
        [string]$ModelPath,
        
        [Parameter(Mandatory=$false)]
        [int]$Port = 8080,
        
        [Parameter(Mandatory=$false)]
        [string]$Host = "127.0.0.1",
        
        [Parameter(Mandatory=$false)]
        [int]$ContextSize = 512,
        
        [Parameter(Mandatory=$false)]
        [int]$Threads = 4,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$AdditionalArgs = @{}
    )
    
    Write-ServerTestLog -Level Info -Message "Starting test server with model: $(Split-Path $ModelPath -Leaf)"
    
    try {
        # Stop any existing server
        Stop-TestServer -Force
        
        # Build server arguments
        $serverArgs = @(
            "-m", $ModelPath,
            "--host", $Host,
            "--port", $Port,
            "-c", $ContextSize,
            "--threads", $Threads
        )
        
        # Add additional arguments
        foreach ($arg in $AdditionalArgs.GetEnumerator()) {
            if ($arg.Value -is [switch] -and $arg.Value.IsPresent) {
                $serverArgs += "--$($arg.Key)"
            } elseif ($arg.Value -is [array]) {
                $serverArgs += "--$($arg.Key)"
                $serverArgs += $arg.Value
            } else {
                $serverArgs += "--$($arg.Key)"
                $serverArgs += $arg.Value
            }
        }
        
        # Start server process
        $scriptDir = Split-Path $PSScriptRoot -Parent
        $serverPath = Join-Path $scriptDir "Tools\bin\llama-server.exe"
        $script:ServerProcess = Start-Process -FilePath $serverPath -ArgumentList $serverArgs -PassThru -NoNewWindow
        
        # Wait for server to initialize
        Write-ServerTestLog -Level Info -Message "Waiting for server initialization..."
        Start-Sleep -Seconds 5
        
        # Check if process is still running
        if ($script:ServerProcess.HasExited) {
            throw "Server failed to start. Exit code: $($script:ServerProcess.ExitCode)"
        }
        
        $metrics = @{
            ProcessId = $script:ServerProcess.Id
            Port = $Port
            Host = $Host
            ModelPath = $ModelPath
            ContextSize = $ContextSize
            Threads = $Threads
            StartTime = Get-Date
        }
        
        Write-TestResult -TestName "Server Startup" -Success $true -Details "Server started successfully" -Metrics $metrics
        return $true
    }
    catch {
        Write-TestResult -TestName "Server Startup" -Success $false -Error $_.Exception.Message
        return $false
    }
}

function Stop-TestServer {
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    if ($script:ServerProcess -and -not $script:ServerProcess.HasExited) {
        Write-ServerTestLog -Level Info -Message "Stopping server process (PID: $($script:ServerProcess.Id))"
        
        try {
            $script:ServerProcess.Kill()
            $script:ServerProcess.WaitForExit(5000) | Out-Null
            
            if (-not $script:ServerProcess.HasExited) {
                if ($Force) {
                    $script:ServerProcess.Kill()
                    Start-Sleep -Seconds 2
                } else {
                    throw "Server process did not terminate gracefully"
                }
            }
            
            Write-ServerTestLog -Level Success -Message "Server stopped successfully"
        }
        catch {
            Write-ServerTestLog -Level Warning -Message "Failed to stop server: $($_.Exception.Message)"
        }
        finally {
            $script:ServerProcess = $null
        }
    }
}

#endregion

#region HTTP Endpoint Testing

function Test-ServerHealth {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Host = "127.0.0.1",
        
        [Parameter(Mandatory=$false)]
        [int]$Port = 8080,
        
        [Parameter(Mandatory=$false)]
        [int]$Timeout = 30,
        
        [Parameter(Mandatory=$false)]
        [int]$RetryInterval = 2
    )
    
    Write-ServerTestLog -Level Info -Message "Testing server health endpoint"
    
    $result = @{
        Success = $false
        Response = $null
        ResponseTime = 0
        Attempts = 0
        Error = $null
    }
    
    $uri = "http://$($Host):$Port/health"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        $maxAttempts = [math]::Floor($Timeout / $RetryInterval)
        
        for ($attempt = 0; $attempt -lt $maxAttempts; $attempt++) {
            $result.Attempts = $attempt + 1
            
            try {
                $response = Invoke-RestMethod -Uri $uri -TimeoutSec $RetryInterval -ErrorAction Stop
                $result.Success = $true
                $result.Response = $response
                $result.ResponseTime = $stopwatch.ElapsedMilliseconds
                
                Write-ServerTestLog -Level Success -Message "Health check successful (attempt $($attempt + 1))"
                break
            }
            catch {
                if ($attempt -eq $maxAttempts - 1) {
                    $result.Error = "Health check failed after $Timeout seconds: $($_.Exception.Message)"
                } else {
                    Write-ServerTestLog -Level Info -Message "Health check attempt $($attempt + 1) failed, retrying..."
                    Start-Sleep -Seconds $RetryInterval
                }
            }
        }
    }
    catch {
        $result.Error = "Health check exception: $($_.Exception.Message)"
    }
    finally {
        $stopwatch.Stop()
    }
    
    $metrics = @{
        ResponseTime = $result.ResponseTime
        Attempts = $result.Attempts
        Timeout = $Timeout
    }
    
    if ($result.Success) {
        Write-TestResult -TestName "Server Health Check" -Success $true -Details "Server responded successfully" -Metrics $metrics
    } else {
        Write-TestResult -TestName "Server Health Check" -Success $false -Error $result.Error -Metrics $metrics
    }
    
    return $result
}

function Test-ServerEndpoints {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Host = "127.0.0.1",
        
        [Parameter(Mandatory=$false)]
        [int]$Port = 8080
    )
    
    Write-ServerTestLog -Level Info -Message "Testing server endpoints"
    
    $endpoints = @(
        @{ Path = "/health"; Method = "GET"; ExpectedStatus = 200; Description = "Health check" },
        @{ Path = "/v1/models"; Method = "GET"; ExpectedStatus = 200; Description = "OpenAI models list" },
        @{ Path = "/props"; Method = "GET"; ExpectedStatus = 200; Description = "Server properties" }
    )
    
    $results = @()
    $successCount = 0
    
    foreach ($endpoint in $endpoints) {
        Write-ServerTestLog -Level Info -Message "Testing $($endpoint.Description): $($endpoint.Path)"
        
        $uri = "http://$($Host):$Port$($endpoint.Path)"
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            $response = Invoke-RestMethod -Uri $uri -Method $endpoint.Method -TimeoutSec 10 -ErrorAction Stop
            $stopwatch.Stop()
            
            $endpointResult = @{
                Path = $endpoint.Path
                Method = $endpoint.Method
                Description = $endpoint.Description
                Success = $true
                Response = $response
                ResponseTime = $stopwatch.ElapsedMilliseconds
                Error = $null
            }
            
            $results += $endpointResult
            $successCount++
            
            Write-ServerTestLog -Level Success -Message "  ✅ $($endpoint.Description) - $($stopwatch.ElapsedMilliseconds)ms"
        }
        catch {
            $stopwatch.Stop()
            
            $endpointResult = @{
                Path = $endpoint.Path
                Method = $endpoint.Method
                Description = $endpoint.Description
                Success = $false
                Response = $null
                ResponseTime = $stopwatch.ElapsedMilliseconds
                Error = $_.Exception.Message
            }
            
            $results += $endpointResult
            
            Write-ServerTestLog -Level Error -Message "  ❌ $($endpoint.Description) - $($_.Exception.Message)"
        }
    }
    
    $metrics = @{
        TotalEndpoints = $endpoints.Count
        SuccessfulEndpoints = $successCount
        FailedEndpoints = $endpoints.Count - $successCount
        SuccessRate = [math]::Round(($successCount / $endpoints.Count) * 100, 2)
    }
    
    $overallSuccess = $successCount -eq $endpoints.Count
    
    if ($overallSuccess) {
        Write-TestResult -TestName "Server Endpoints" -Success $true -Details "All $($endpoints.Count) endpoints tested successfully" -Metrics $metrics
    } else {
        Write-TestResult -TestName "Server Endpoints" -Success $false -Details "$successCount/$($endpoints.Count) endpoints successful" -Metrics $metrics
    }
    
    return @{ Success = $overallSuccess; Results = $results; Metrics = $metrics }
}

#endregion

#region Performance Monitoring

function Get-ServerPerformanceMetrics {
    param(
        [Parameter(Mandatory=$false)]
        [int]$ProcessId = $script:ServerProcess.Id
    )
    
    if (-not $ProcessId) {
        return @{ Error = "No process ID provided" }
    }
    
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        
        # Get system performance counters
        $cpuCounter = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
        $memoryCounter = Get-Counter "\Memory\Available MBytes" -ErrorAction SilentlyContinue
        
        $metrics = @{
            ProcessId = $ProcessId
            ProcessName = $process.ProcessName
            CpuUsage = if ($cpuCounter) { [math]::Round($cpuCounter.CounterSamples.CookedValue, 2) } else { 0 }
            MemoryMB = [math]::Round($process.WorkingSet64 / 1MB, 2)
            AvailableMemoryMB = if ($memoryCounter) { [math]::Round($memoryCounter.CounterSamples.CookedValue, 2) } else { 0 }
            ThreadCount = $process.Threads.Count
            HandleCount = $process.HandleCount
            StartTime = $process.StartTime
            Timestamp = Get-Date
        }
        
        return $metrics
    }
    catch {
        return @{ Error = $_.Exception.Message }
    }
}

function Start-PerformanceMonitoring {
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId,
        
        [Parameter(Mandatory=$false)]
        [int]$IntervalSeconds = 5,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxSamples = 60
    )
    
    Write-ServerTestLog -Level Info -Message "Starting performance monitoring for PID: $ProcessId"
    
    $monitoringData = @()
    $sampleCount = 0
    
    while ($sampleCount -lt $MaxSamples) {
        $metrics = Get-ServerPerformanceMetrics -ProcessId $ProcessId
        
        if ($metrics.Error) {
            Write-ServerTestLog -Level Warning -Message "Performance monitoring error: $($metrics.Error)"
            break
        }
        
        $monitoringData += $metrics
        $sampleCount++
        
        Write-ServerTestLog -Level Info -Message "Sample $($sampleCount): CPU $($metrics.CpuUsage)%, Memory $($metrics.MemoryMB)MB"
        
        Start-Sleep -Seconds $IntervalSeconds
    }
    
    # Calculate statistics
    if ($monitoringData.Count -gt 0) {
        $avgCpu = [math]::Round(($monitoringData | Measure-Object -Property CpuUsage -Average).Average, 2)
        $maxCpu = [math]::Round(($monitoringData | Measure-Object -Property CpuUsage -Maximum).Maximum, 2)
        $avgMemory = [math]::Round(($monitoringData | Measure-Object -Property MemoryMB -Average).Average, 2)
        $maxMemory = [math]::Round(($monitoringData | Measure-Object -Property MemoryMB -Maximum).Maximum, 2)
        
        $stats = @{
            SampleCount = $monitoringData.Count
            Duration = $sampleCount * $IntervalSeconds
            AvgCpuUsage = $avgCpu
            MaxCpuUsage = $maxCpu
            AvgMemoryMB = $avgMemory
            MaxMemoryMB = $maxMemory
            Data = $monitoringData
        }
        
        Write-TestResult -TestName "Performance Monitoring" -Success $true -Details "Collected $($monitoringData.Count) samples" -Metrics $stats
        return $stats
    } else {
        Write-TestResult -TestName "Performance Monitoring" -Success $false -Error "No performance data collected"
        return $null
    }
}

#endregion

#region Comprehensive Test Suite

function Invoke-CompleteServerTest {
    param(
        [Parameter(Mandatory=$false)]
        [string]$ModelPath,
        
        [Parameter(Mandatory=$false)]
        [int]$Port = 8080,
        
        [Parameter(Mandatory=$false)]
        [switch]$IncludePerformanceTest,
        
        [Parameter(Mandatory=$false)]
        [switch]$Detailed
    )
    
    Write-ServerTestLog -Level Info -Message "Starting comprehensive server test suite"
    Write-ServerTestLog -Level Info -Message "Log file: $script:LogFile"
    
    $overallSuccess = $true
    $startTime = Get-Date
    
    try {
        # Step 1: Initialize test models
        if (-not (Initialize-TestModels)) {
            throw "Failed to initialize test models"
        }
        
        # Step 2: Select test model
        if (-not $ModelPath) {
            $testModel = Get-OptimalTestModel -Preference "fastest"
            if (-not $testModel) {
                throw "No suitable test model found"
            }
            $ModelPath = $testModel.Path
        }
        
        Write-ServerTestLog -Level Info -Message "Using test model: $(Split-Path $ModelPath -Leaf)"
        
        # Step 3: Test server dependencies
        $scriptDir = Split-Path $PSScriptRoot -Parent
        $serverPath = Join-Path $scriptDir "Tools\bin\llama-server.exe"
        $dependencyTest = Test-ServerDependencies -ServerPath $serverPath
        if (-not $dependencyTest.Success) {
            throw "Server dependency test failed"
        }
        
        # Step 4: Test binary integrity
        $integrityTest = Test-BinaryIntegrity -BinaryPath $serverPath
        if (-not $integrityTest) {
            throw "Binary integrity test failed"
        }
        
        # Step 5: Start server
        if (-not (Start-TestServer -ModelPath $ModelPath -Port $Port)) {
            throw "Failed to start server"
        }
        
        # Step 6: Test health endpoint
        $healthTest = Test-ServerHealth -Port $Port
        if (-not $healthTest.Success) {
            throw "Health check failed"
        }
        
        # Step 7: Test all endpoints
        $endpointTest = Test-ServerEndpoints -Port $Port
        if (-not $endpointTest.Success) {
            Write-ServerTestLog -Level Warning -Message "Some endpoints failed"
            $overallSuccess = $false
        }
        
        # Step 8: Performance monitoring (optional)
        if ($IncludePerformanceTest) {
            Write-ServerTestLog -Level Info -Message "Starting performance monitoring..."
            $perfStats = Start-PerformanceMonitoring -ProcessId $script:ServerProcess.Id -IntervalSeconds 2 -MaxSamples 30
            if ($perfStats) {
                Write-ServerTestLog -Level Info -Message "Performance: Avg CPU $($perfStats.AvgCpuUsage)%, Avg Memory $($perfStats.AvgMemoryMB)MB"
            }
        }
        
        # Step 9: Generate test report
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        $summary = @{
            OverallSuccess = $overallSuccess
            TotalTests = $script:TestResults.Count
            SuccessfulTests = ($script:TestResults | Where-Object { $_.Success }).Count
            FailedTests = ($script:TestResults | Where-Object { -not $_.Success }).Count
            Duration = [math]::Round($duration, 2)
            StartTime = $startTime
            EndTime = $endTime
            ModelUsed = Split-Path $ModelPath -Leaf
            ServerPort = $Port
            TestResults = $script:TestResults
        }
        
        Write-ServerTestLog -Level Success -Message "Test suite completed in $($summary.Duration) seconds"
        Write-ServerTestLog -Level Info -Message "Results: $($summary.SuccessfulTests)/$($summary.TotalTests) tests passed"
        
        if ($Detailed) {
            $reportPath = "Reports\server_test_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
            $reportDir = Split-Path $reportPath -Parent
            if (-not (Test-Path $reportDir)) {
                New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
            }
            $summary | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath
            Write-ServerTestLog -Level Info -Message "Detailed report saved to: $reportPath"
        }
        
        return $summary
    }
    catch {
        Write-TestResult -TestName "Complete Server Test" -Success $false -Error $_.Exception.Message
        return @{ OverallSuccess = $false; Error = $_.Exception.Message }
    }
    finally {
        # Cleanup
        Stop-TestServer -Force
    }
}

#endregion

#region Script Entry Point

# Main execution - run comprehensive test suite
if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Name) {
    Write-Host "Starting LLM Server Testing Framework..." -ForegroundColor Green
    $result = Invoke-CompleteServerTest -IncludePerformanceTest -Detailed
    
    if ($result.OverallSuccess) {
        Write-Host "✅ All tests completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "❌ Some tests failed. Check logs for details." -ForegroundColor Red
    }
    
    Write-Host "Log file: $script:LogFile" -ForegroundColor Gray
}

#endregion

Write-Host "LLM Server Testing Framework Loaded!" -ForegroundColor Green
Write-Host "Comprehensive llama-server.exe testing suite ready" -ForegroundColor Cyan
Write-Host "Log file: $script:LogFile" -ForegroundColor Gray
