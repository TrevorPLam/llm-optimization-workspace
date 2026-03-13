<#
.SYNOPSIS
    Automated Binary Integrity Regression Testing
.DESCRIPTION
    Automated regression testing for ongoing binary integrity validation
    Implements scheduled verification and alerting for integrity failures
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "config.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$AlertOnFailure,
    
    [Parameter(Mandatory = $false)]
    [string]$AlertEmail,
    
    [Parameter(Mandatory = $false)]
    [switch]$GenerateReport,
    
    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

# Initialize
$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = "Logs\regression_test_$timestamp.log"

# Ensure directories exist
if (-not (Test-Path "Logs")) { New-Item -ItemType Directory -Path "Logs" -Force | Out-Null }
if (-not (Test-Path "Reports")) { New-Item -ItemType Directory -Path "Reports" -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "$ts - [$Level] $Message"
    Add-Content -Path $logPath -Value $logLine
    if (-not $Quiet) {
        switch ($Level) {
            "INFO" { Write-Host $logLine -ForegroundColor White }
            "SUCCESS" { Write-Host $logLine -ForegroundColor Green }
            "ERROR" { Write-Error $logLine }
            "WARN" { Write-Warning $logLine }
        }
    }
}

function Test-BinaryIntegrityRegression {
    param([string]$ConfigPath = "config.json")
    
    Write-Log "Starting regression integrity test"
    
    try {
        # Load configuration
        $config = Get-Content $ConfigPath | ConvertFrom-Json
        $binaryPaths = $config.binary_paths
        
        # Check if we have checksums
        if (-not ($config.PSObject.Properties.Name -contains "binary_checksums")) {
            Write-Log "No checksums found in configuration" "WARN"
            return @{
                Success = $false
                Message = "No checksums found in configuration"
                Results = @{}
            }
        }
        
        $storedChecksums = $config.binary_checksums
        $results = @{}
        $totalBinaries = 0
        $passedBinaries = 0
        $failedBinaries = 0
        $missingBinaries = 0
        
        # Test each binary
        foreach ($binaryName in $binaryPaths.PSObject.Properties.Name) {
            $binaryPath = $binaryPaths.$binaryName
            $totalBinaries++
            
            Write-Log "Testing: $binaryName"
            
            $result = @{
                BinaryName = $binaryName
                BinaryPath = $binaryPath
                Status = "Unknown"
                StoredHash = $null
                CurrentHash = $null
                HashMatch = $false
                FileSize = 0
                StoredSize = 0
                SizeMatch = $false
                Error = $null
                TestTime = Get-Date
            }
            
            try {
                # Check if file exists
                if (-not (Test-Path $binaryPath)) {
                    $result.Status = "Missing"
                    $result.Error = "Binary file not found"
                    $missingBinaries++
                    Write-Log "✗ Missing: $binaryName" "ERROR"
                } else {
                    # Get current file info
                    $fileInfo = Get-Item $binaryPath
                    $result.FileSize = $fileInfo.Length
                    
                    # Get stored checksum info
                    if ($storedChecksums.PSObject.Properties.Name -contains $binaryName) {
                        $storedInfo = $storedChecksums.$binaryName
                        $result.StoredHash = $storedInfo.hash
                        $result.StoredSize = $storedInfo.file_size
                        
                        # Calculate current hash
                        $currentHash = Get-FileHash -Path $binaryPath -Algorithm SHA256
                        $result.CurrentHash = $currentHash.Hash
                        
                        # Compare hashes
                        $result.HashMatch = ($result.CurrentHash -eq $result.StoredHash)
                        $result.SizeMatch = ($result.FileSize -eq $result.StoredSize)
                        
                        if ($result.HashMatch -and $result.SizeMatch) {
                            $result.Status = "Passed"
                            $passedBinaries++
                            Write-Log "✓ Passed: $binaryName" "SUCCESS"
                        } else {
                            $result.Status = "Failed"
                            $failedBinaries++
                            $result.Error = if (-not $result.HashMatch) { "Hash mismatch" } else { "Size mismatch" }
                            Write-Log "✗ Failed: $binaryName - $($result.Error)" "ERROR"
                        }
                    } else {
                        $result.Status = "NoBaseline"
                        $result.Error = "No stored checksum found for comparison"
                        Write-Log "? No baseline: $binaryName" "WARN"
                    }
                }
                
            } catch {
                $result.Status = "Error"
                $result.Error = $_.Exception.Message
                $failedBinaries++
                Write-Log "✗ Error: $binaryName - $($_.Exception.Message)" "ERROR"
            }
            
            $results[$binaryName] = $result
        }
        
        # Generate summary
        $summary = @{
            TotalBinaries = $totalBinaries
            PassedBinaries = $passedBinaries
            FailedBinaries = $failedBinaries
            MissingBinaries = $missingBinaries
            SuccessRate = if ($totalBinaries -gt 0) { [math]::Round(($passedBinaries / $totalBinaries) * 100, 2) } else { 0 }
            TestTime = Get-Date
        }
        
        $testResult = @{
            Success = ($failedBinaries -eq 0 -and $missingBinaries -eq 0)
            Message = if ($failedBinaries -eq 0 -and $missingBinaries -eq 0) { 
                "All binaries passed integrity check" 
            } else { 
                "$failedBinaries failed, $missingBinaries missing" 
            }
            Summary = $summary
            Results = $results
        }
        
        Write-Log "Regression test completed: $($testResult.Message)"
        Write-Log "Success rate: $($summary.SuccessRate)% ($($passedBinaries)/$($totalBinaries))"
        
        return $testResult
        
    } catch {
        Write-Log "Regression test failed: $($_.Exception.Message)" "ERROR"
        return @{
            Success = $false
            Message = $_.Exception.Message
            Results = @{}
        }
    }
}

function Send-IntegrityAlert {
    param(
        [hashtable]$TestResult,
        [string]$AlertEmail
    )
    
    if (-not $AlertEmail) {
        Write-Log "No alert email specified" "WARN"
        return
    }
    
    try {
        $subject = "Binary Integrity Alert - $(if ($TestResult.Success) { 'PASSED' } else { 'FAILED' })"
        $body = @"
Binary Integrity Regression Test Results

Status: $($TestResult.Message)
Test Time: $(Get-Date)

Summary:
Total Binaries: $($TestResult.Summary.TotalBinaries)
Passed: $($TestResult.Summary.PassedBinaries)
Failed: $($TestResult.Summary.FailedBinaries)
Missing: $($TestResult.Summary.MissingBinaries)
Success Rate: $($TestResult.Summary.SuccessRate)%

Detailed Results:
"@
        
        foreach ($binaryName in $TestResult.Results.Keys) {
            $result = $TestResult.Results[$binaryName]
            $body += "`n$($result.BinaryName): $($result.Status)"
            if ($result.Error) {
                $body += " - $($result.Error)"
            }
        }
        
        $body += "`n`nLog file: $logPath"
        
        # Send email (would require email configuration)
        Write-Log "Alert email would be sent to: $AlertEmail" "INFO"
        Write-Log "Subject: $subject" "INFO"
        Write-Log "Body: $($body.Length) characters" "INFO"
        
    } catch {
        Write-Log "Failed to send alert: $($_.Exception.Message)" "ERROR"
    }
}

# Main execution
if (-not $Quiet) {
    Write-Host "🔍 Binary Integrity Regression Test" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
}

# Run regression test
$testResult = Test-BinaryIntegrityRegression -ConfigPath $ConfigPath

# Generate report if requested
if ($GenerateReport) {
    $reportPath = "Reports\regression_test_$timestamp.json"
    $testResult | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Log "Report saved to: $reportPath"
}

# Send alert if requested
if ($AlertOnFailure -and -not $testResult.Success) {
    Send-IntegrityAlert -TestResult $testResult -AlertEmail $AlertEmail
}

# Exit with appropriate code
if ($testResult.Success) {
    Write-Log "Regression test PASSED" "SUCCESS"
    exit 0
} else {
    Write-Log "Regression test FAILED" "ERROR"
    exit 1
}
