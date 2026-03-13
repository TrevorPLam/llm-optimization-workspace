# Binary Integrity Regression Test - Final Working Version
Write-Host "🔍 Binary Integrity Regression Test" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

# Initialize
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = "Logs\regression_test_$timestamp.log"

# Ensure log directory exists
if (-not (Test-Path "Logs")) { 
    New-Item -ItemType Directory -Path "Logs" -Force | Out-Null 
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "$ts - [$Level] $Message"
    Add-Content -Path $logPath -Value $logLine
    Write-Host $logLine
}

Write-Log "Starting regression integrity test"

try {
    # Load configuration
    $config = Get-Content "config.json" | ConvertFrom-Json
    $binaryPaths = $config.binary_paths
    
    # Check if we have checksums
    if (-not ($config.PSObject.Properties.Name -contains "binary_checksums")) {
        Write-Log "No checksums found in configuration" "WARN"
        exit 1
    }
    
    $storedChecksums = $config.binary_checksums
    $totalBinaries = $binaryPaths.PSObject.Properties.Name.Count
    $passedBinaries = 0
    $failedBinaries = 0
    $missingBinaries = 0
    
    Write-Log "Testing $totalBinaries binaries against stored checksums"
    
    # Test each binary
    foreach ($binaryName in $binaryPaths.PSObject.Properties.Name) {
        $binaryPath = $binaryPaths.$binaryName
        Write-Log "Testing: $binaryName"
        
        if (-not (Test-Path $binaryPath)) {
            Write-Log "✗ Missing: $binaryName" "ERROR"
            $missingBinaries++
            continue
        }
        
        if (-not ($storedChecksums.PSObject.Properties.Name -contains $binaryName)) {
            Write-Log "? No baseline: $binaryName" "WARN"
            continue
        }
        
        try {
            $storedInfo = $storedChecksums.$binaryName
            $storedHash = $storedInfo.hash
            
            # Calculate current hash
            $currentHash = Get-FileHash -Path $binaryPath -Algorithm SHA256
            
            # Compare hashes
            if ($currentHash.Hash -eq $storedHash) {
                Write-Log "✓ Passed: $binaryName" "SUCCESS"
                $passedBinaries++
            } else {
                Write-Log "✗ Failed: $binaryName - Hash mismatch" "ERROR"
                $failedBinaries++
            }
            
        } catch {
            Write-Log "✗ Error: $binaryName - $($_.Exception.Message)" "ERROR"
            $failedBinaries++
        }
    }
    
    # Generate summary
    $successRate = if ($totalBinaries -gt 0) { [math]::Round(($passedBinaries / $totalBinaries) * 100, 2) } else { 0 }
    
    Write-Log "Regression test completed"
    Write-Log "Results: $passedBinaries passed, $failedBinaries failed, $missingBinaries missing"
    Write-Log "Success rate: $successRate%"
    
    # Display summary
    Write-Host ""
    Write-Host "📊 Test Summary" -ForegroundColor Green
    Write-Host "===============" -ForegroundColor Green
    Write-Host "Total Binaries: $totalBinaries"
    Write-Host "Passed: $passedBinaries" -ForegroundColor Green
    Write-Host "Failed: $failedBinaries" -ForegroundColor Red
    Write-Host "Missing: $missingBinaries" -ForegroundColor Yellow
    Write-Host "Success Rate: $successRate%"
    
    # Save report
    $reportPath = "Reports\regression_test_$timestamp.json"
    if (-not (Test-Path "Reports")) { 
        New-Item -ItemType Directory -Path "Reports" -Force | Out-Null 
    }
    
    $report = @{
        Timestamp = Get-Date
        Summary = @{
            TotalBinaries = $totalBinaries
            PassedBinaries = $passedBinaries
            FailedBinaries = $failedBinaries
            MissingBinaries = $missingBinaries
            SuccessRate = $successRate
        }
        Success = ($failedBinaries -eq 0 -and $missingBinaries -eq 0)
        LogPath = $logPath
    }
    
    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host ""
    Write-Host "📄 Report saved to: $reportPath" -ForegroundColor Green
    Write-Host "📝 Log file: $logPath" -ForegroundColor Green
    
    # Exit with appropriate code
    if ($failedBinaries -eq 0 -and $missingBinaries -eq 0) {
        Write-Log "Regression test PASSED" "SUCCESS"
        exit 0
    } else {
        Write-Log "Regression test FAILED" "ERROR"
        exit 1
    }
    
} catch {
    Write-Log "Regression test failed: $($_.Exception.Message)" "ERROR"
    Write-Error "Regression test failed: $($_.Exception.Message)"
    exit 1
}
