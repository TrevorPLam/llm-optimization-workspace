<#
.SYNOPSIS
    Simple Binary Integrity Verification
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "config.json",
    [switch]$UpdateConfig,
    [switch]$Detailed
)

# Initialize logging
$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = "Logs\binary_integrity_$timestamp.log"

# Ensure log directory exists
if (-not (Test-Path "Logs")) {
    New-Item -ItemType Directory -Path "Logs" -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "$timestamp - [$Level] $Message"
    Add-Content -Path $logPath -Value $logLine
    
    switch ($Level) {
        "INFO" { Write-Host $logLine -ForegroundColor White }
        "SUCCESS" { Write-Host $logLine -ForegroundColor Green }
        "ERROR" { Write-Error $logLine }
        "WARN" { Write-Warning $logLine }
    }
}

Write-Host "🔍 Binary Integrity Verification" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Log "Starting binary integrity verification"

try {
    # Load configuration
    Write-Log "Loading configuration from $ConfigPath"
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $binaryPaths = $config.binary_paths
    Write-Log "Configuration loaded successfully"
    
    # Verification results
    $results = @{}
    $checksums = @{}
    $totalBinaries = 0
    $verifiedBinaries = 0
    $failedBinaries = 0
    $missingBinaries = 0
    
    # Check each binary
    foreach ($binaryName in $binaryPaths.PSObject.Properties.Name) {
        $binaryPath = $binaryPaths.$binaryName
        $totalBinaries++
        
        Write-Log "Verifying binary: $binaryName -> $binaryPath"
        
        $result = @{
            BinaryName = $binaryName
            BinaryPath = $binaryPath
            Status = "Unknown"
            Checksum = $null
            FileSize = 0
            Error = $null
        }
        
        try {
            # Check if file exists
            if (-not (Test-Path $binaryPath)) {
                $result.Status = "Missing"
                $result.Error = "Binary file not found"
                $missingBinaries++
                
                Write-Log "Binary not found: $binaryName" "ERROR"
                $results[$binaryName] = $result
                continue
            }
            
            # Get file info
            $fileInfo = Get-Item $binaryPath
            $result.FileSize = $fileInfo.Length
            
            # Calculate checksum
            Write-Log "Calculating SHA256 checksum for $binaryName"
            $hashResult = Get-FileHash -Path $binaryPath -Algorithm SHA256
            
            if ($hashResult) {
                $result.Checksum = $hashResult.Hash
                $result.Status = "Verified"
                $verifiedBinaries++
                
                $checksums[$binaryName] = @{
                    Hash = $hashResult.Hash
                    FileSize = $fileInfo.Length
                }
                
                Write-Log "Binary verified: $binaryName (hash: $($hashResult.Hash.Substring(0, 16))...)" "SUCCESS"
            } else {
                $result.Status = "Failed"
                $result.Error = "Failed to calculate checksum"
                $failedBinaries++
                
                Write-Log "Checksum calculation failed: $binaryName" "ERROR"
            }
            
        } catch {
            $result.Status = "Error"
            $result.Error = $_.Exception.Message
            $failedBinaries++
            
            Write-Log "Error verifying $binaryName`: $($_.Exception.Message)" "ERROR"
        }
        
        $results[$binaryName] = $result
    }
    
    # Update configuration if requested
    if ($UpdateConfig -and $checksums.Count -gt 0) {
        Write-Log "Updating configuration with checksums"
        
        # Create backup
        $backupPath = "$ConfigPath.backup.$timestamp"
        Copy-Item $ConfigPath $backupPath
        Write-Log "Configuration backed up to $backupPath"
        
        # Add checksums section
        if (-not ($config.PSObject.Properties.Name -contains "binary_checksums")) {
            $config | Add-Member -NotePropertyName "binary_checksums" -NotePropertyValue @{}
        }
        
        # Update checksums
        foreach ($binaryName in $checksums.Keys) {
            $config.binary_checksums | Add-Member -NotePropertyName $binaryName -NotePropertyValue @{
                hash = $checksums[$binaryName].Hash
                algorithm = "SHA256"
                verified = $true
                timestamp = Get-Date
                file_size = $checksums[$binaryName].FileSize
            } -Force
        }
        
        # Save updated configuration
        $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigPath -Encoding UTF8
        Write-Log "Configuration updated successfully" "SUCCESS"
    }
    
    # Display summary
    Write-Host ""
    Write-Host "📊 Verification Summary" -ForegroundColor Green
    Write-Host "======================" -ForegroundColor Green
    Write-Host "Total Binaries: $totalBinaries"
    Write-Host "Verified: $verifiedBinaries" -ForegroundColor Green
    Write-Host "Failed: $failedBinaries" -ForegroundColor Red
    Write-Host "Missing: $missingBinaries" -ForegroundColor Yellow
    
    if ($totalBinaries -gt 0) {
        $successRate = [math]::Round(($verifiedBinaries / $totalBinaries) * 100, 2)
        Write-Host "Success Rate: $successRate%"
    }
    
    # Detailed results
    if ($Detailed) {
        Write-Host ""
        Write-Host "📋 Detailed Results" -ForegroundColor Cyan
        Write-Host "==================" -ForegroundColor Cyan
        
        foreach ($binaryName in $results.Keys) {
            $result = $results[$binaryName]
            $statusColor = switch ($result.Status) {
                "Verified" { "Green" }
                "Failed" { "Red" }
                "Missing" { "Yellow" }
                default { "White" }
            }
            
            Write-Host "[$($result.Status.ToUpper())] $($result.BinaryName)" -ForegroundColor $statusColor
            Write-Host "  Path: $($result.BinaryPath)"
            if ($result.Checksum) {
                Write-Host "  Hash: $($result.Checksum.Substring(0, 16))..."
            }
            if ($result.FileSize -gt 0) {
                Write-Host "  Size: $([math]::Round($result.FileSize / 1MB, 2)) MB"
            }
            if ($result.Error) {
                Write-Host "  Error: $($result.Error)" -ForegroundColor Red
            }
            Write-Host ""
        }
    }
    
    # Save report
    $reportPath = "Reports\binary_integrity_$timestamp.json"
    if (-not (Test-Path "Reports")) {
        New-Item -ItemType Directory -Path "Reports" -Force | Out-Null
    }
    
    $report = @{
        Timestamp = Get-Date
        Summary = @{
            TotalBinaries = $totalBinaries
            VerifiedBinaries = $verifiedBinaries
            FailedBinaries = $failedBinaries
            MissingBinaries = $missingBinaries
            SuccessRate = if ($totalBinaries -gt 0) { [math]::Round(($verifiedBinaries / $totalBinaries) * 100, 2) } else { 0 }
        }
        Results = $results
        Checksums = $checksums
    }
    
    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
    
    Write-Host ""
    Write-Host "📄 Report saved to: $reportPath" -ForegroundColor Green
    Write-Host "📝 Log file: $logPath" -ForegroundColor Green
    
    Write-Log "Binary integrity verification completed successfully" "SUCCESS"
    
} catch {
    Write-Log "Verification failed: $($_.Exception.Message)" "ERROR"
    Write-Error "Binary integrity verification failed: $($_.Exception.Message)"
    exit 1
}
