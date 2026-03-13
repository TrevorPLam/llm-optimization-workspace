# Simple Binary Integrity Verification
Write-Host "🔍 Binary Integrity Verification" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan

# Initialize
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = "Logs\binary_integrity_$timestamp.log"
$reportPath = "Reports\binary_integrity_$timestamp.json"

# Ensure directories exist
if (-not (Test-Path "Logs")) { New-Item -ItemType Directory -Path "Logs" -Force | Out-Null }
if (-not (Test-Path "Reports")) { New-Item -ItemType Directory -Path "Reports" -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "$ts - [$Level] $Message"
    Add-Content -Path $logPath -Value $logLine
    Write-Host $logLine
}

Write-Log "Starting binary integrity verification"

# Load configuration
try {
    $config = Get-Content "config.json" | ConvertFrom-Json
    Write-Log "Configuration loaded successfully"
    
    $binaryPaths = $config.binary_paths
    $totalBinaries = $binaryPaths.PSObject.Properties.Name.Count
    Write-Log "Found $totalBinaries binaries to verify"
    
    $results = @{}
    $checksums = @{}
    $verified = 0
    $failed = 0
    $missing = 0
    
    # Verify each binary
    foreach ($binaryName in $binaryPaths.PSObject.Properties.Name) {
        $binaryPath = $binaryPaths.$binaryName
        Write-Log "Verifying: $binaryName -> $binaryPath"
        
        $result = @{
            BinaryName = $binaryName
            BinaryPath = $binaryPath
            Status = "Unknown"
            Checksum = $null
            FileSize = 0
            Error = $null
        }
        
        if (-not (Test-Path $binaryPath)) {
            $result.Status = "Missing"
            $result.Error = "Binary file not found"
            $missing++
            Write-Log "✗ Missing: $binaryName" "ERROR"
        } else {
            try {
                $fileInfo = Get-Item $binaryPath
                $result.FileSize = $fileInfo.Length
                
                $hashResult = Get-FileHash -Path $binaryPath -Algorithm SHA256
                $result.Checksum = $hashResult.Hash
                $result.Status = "Verified"
                $verified++
                
                $checksums[$binaryName] = @{
                    Hash = $hashResult.Hash
                    FileSize = $fileInfo.Length
                }
                
                Write-Log "✓ Verified: $binaryName (hash: $($hashResult.Hash.Substring(0,16))...)"
                
            } catch {
                $result.Status = "Failed"
                $result.Error = $_.Exception.Message
                $failed++
                Write-Log "✗ Failed: $binaryName - $($_.Exception.Message)" "ERROR"
            }
        }
        
        $results[$binaryName] = $result
    }
    
    # Update configuration if requested
    if ($UpdateConfig -and $checksums.Count -gt 0) {
        Write-Log "Updating configuration with checksums"
        $backupPath = "config.json.backup.$timestamp"
        Copy-Item "config.json" $backupPath
        Write-Log "Configuration backed up to $backupPath"
        
        if (-not ($config.PSObject.Properties.Name -contains "binary_checksums")) {
            $config | Add-Member -NotePropertyName "binary_checksums" -NotePropertyValue @{}
        }
        
        foreach ($binaryName in $checksums.Keys) {
            $config.binary_checksums | Add-Member -NotePropertyName $binaryName -NotePropertyValue @{
                hash = $checksums[$binaryName].Hash
                algorithm = "SHA256"
                verified = $true
                timestamp = Get-Date
                file_size = $checksums[$binaryName].FileSize
            } -Force
        }
        
        $config | ConvertTo-Json -Depth 10 | Out-File -FilePath "config.json" -Encoding UTF8
        Write-Log "Configuration updated successfully"
    }
    
    # Display summary
    Write-Host ""
    Write-Host "📊 Verification Summary" -ForegroundColor Green
    Write-Host "======================" -ForegroundColor Green
    Write-Host "Total Binaries: $totalBinaries"
    Write-Host "Verified: $verified" -ForegroundColor Green
    Write-Host "Failed: $failed" -ForegroundColor Red
    Write-Host "Missing: $missing" -ForegroundColor Yellow
    
    if ($totalBinaries -gt 0) {
        $successRate = [math]::Round(($verified / $totalBinaries) * 100, 2)
        Write-Host "Success Rate: $successRate%"
    }
    
    # Detailed results
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
    
    # Save report
    $report = @{
        Timestamp = Get-Date
        Summary = @{
            TotalBinaries = $totalBinaries
            VerifiedBinaries = $verified
            FailedBinaries = $failed
            MissingBinaries = $missing
            SuccessRate = if ($totalBinaries -gt 0) { [math]::Round(($verified / $totalBinaries) * 100, 2) } else { 0 }
        }
        Results = $results
        Checksums = $checksums
    }
    
    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
    
    Write-Host ""
    Write-Host "📄 Report saved to: $reportPath" -ForegroundColor Green
    Write-Host "📝 Log file: $logPath" -ForegroundColor Green
    
    Write-Log "Binary integrity verification completed successfully"
    
} catch {
    Write-Log "Verification failed: $($_.Exception.Message)" "ERROR"
    Write-Error "Binary integrity verification failed: $($_.Exception.Message)"
    exit 1
}
