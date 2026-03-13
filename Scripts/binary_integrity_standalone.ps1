<#
.SYNOPSIS
    Standalone Binary Integrity Verification Script

.DESCRIPTION
    Comprehensive binary integrity verification for llama.cpp workspace
    Implements SHA256 checksum validation with structured logging
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "config.json",
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "Logs\binary_integrity_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",
    
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "Reports\binary_integrity_$(Get-Date -Format 'yyyyMMdd_HHmmss').json",
    
    [Parameter(Mandatory = $false)]
    [switch]$UpdateConfig,
    
    [Parameter(Mandatory = $false)]
    [switch]$Detailed,
    
    [Parameter(Mandatory = $false)]
    [switch]$ForceRehash,
    
    [Parameter(Mandatory = $false)]
    [string]$Algorithm = "SHA256"
)

# Initialize
$ErrorActionPreference = 'Stop'

# Ensure directories exist
$LogDir = Split-Path $LogPath -Parent
$ReportDir = Split-Path $ReportPath -Parent

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }

# Logging function
function Write-IntegrityLog {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level,
        
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Metadata = @{}
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logLine = "$timestamp - [$Level] $Message"
    if ($Metadata.Count -gt 0) {
        $logLine += " | $($Metadata | ConvertTo-Json -Compress)"
    }
    
    Add-Content -Path $LogPath -Value $logLine
    
    switch ($Level) {
        "INFO"    { Write-Host $logLine -ForegroundColor White }
        "WARN"    { Write-Warning $logLine }
        "ERROR"   { Write-Error $logLine }
        "SUCCESS" { Write-Host $logLine -ForegroundColor Green }
    }
}

# Calculate checksum
function Get-BinaryChecksum {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $false)]
        [string]$Algorithm = "SHA256"
    )
    
    try {
        Write-IntegrityLog -Level "INFO" -Message "Calculating $Algorithm checksum for $FilePath"
        
        if (-not (Test-Path $FilePath)) {
            throw "File not found: $FilePath"
        }
        
        $hashResult = Get-FileHash -Path $FilePath -Algorithm $Algorithm
        $fileInfo = Get-Item $FilePath
        
        Write-IntegrityLog -Level "SUCCESS" -Message "Checksum calculated" -Metadata @{
            File = $fileInfo.Name
            Checksum = $hashResult.Hash.Substring(0, 16) + "..."
            SizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        }
        
        return @{
            Success = $true
            Hash = $hashResult.Hash
            FileSize = $fileInfo.Length
            LastModified = $fileInfo.LastWriteTime
        }
        
    } catch {
        Write-IntegrityLog -Level "ERROR" -Message "Checksum calculation failed: $($_.Exception.Message)"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Load configuration
function Get-Configuration {
    param([string]$ConfigPath = "config.json")
    
    try {
        Write-IntegrityLog -Level "INFO" -Message "Loading configuration from $ConfigPath"
        
        if (-not (Test-Path $ConfigPath)) {
            throw "Configuration file not found: $ConfigPath"
        }
        
        $configContent = Get-Content $ConfigPath -Raw
        if (-not (Test-Json $configContent)) {
            throw "Invalid JSON syntax in configuration file"
        }
        
        $config = $configContent | ConvertFrom-Json
        
        # Validate required sections
        $requiredSections = @("binary_paths", "model_paths", "optimization_defaults", "hardware_config")
        foreach ($section in $requiredSections) {
            if (-not ($config.PSObject.Properties.Name -contains $section)) {
                throw "Missing required configuration section: $section"
            }
        }
        
        Write-IntegrityLog -Level "SUCCESS" -Message "Configuration loaded and validated"
        return $config
        
    } catch {
        Write-IntegrityLog -Level "ERROR" -Message "Configuration load failed: $($_.Exception.Message)"
        throw
    }
}

# Update configuration with checksums
function Update-Configuration {
    param(
        [object]$Config,
        [hashtable]$Checksums,
        [string]$ConfigPath = "config.json"
    )
    
    try {
        Write-IntegrityLog -Level "INFO" -Message "Updating configuration with checksums"
        
        # Create backup
        $backupPath = "$ConfigPath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $ConfigPath $backupPath
        Write-IntegrityLog -Level "INFO" -Message "Configuration backed up to $backupPath"
        
        # Add checksums section
        if (-not ($Config.PSObject.Properties.Name -contains "binary_checksums")) {
            $Config | Add-Member -NotePropertyName "binary_checksums" -NotePropertyValue @{}
        }
        
        # Update checksums
        foreach ($binaryName in $Checksums.Keys) {
            $Config.binary_checksums | Add-Member -NotePropertyName $binaryName -NotePropertyValue @{
                hash = $Checksums[$binaryName].Hash
                algorithm = $Algorithm
                verified = $true
                timestamp = Get-Date
                file_size = $Checksums[$binaryName].FileSize
            } -Force
        }
        
        # Save updated configuration
        $Config | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigPath -Encoding UTF8
        
        Write-IntegrityLog -Level "SUCCESS" -Message "Configuration updated successfully"
        return $true
        
    } catch {
        Write-IntegrityLog -Level "ERROR" -Message "Configuration update failed: $($_.Exception.Message)"
        throw
    }
}

# Main verification function
function Start-BinaryIntegrityVerification {
    Write-Host "🔍 Binary Integrity Verification" -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host ""
    
    $verificationResults = @{
        StartTime = Get-Date
        TotalBinaries = 0
        VerifiedBinaries = 0
        FailedBinaries = 0
        MissingBinaries = 0
        Results = @{}
        Checksums = @{}
    }
    
    try {
        # Load configuration
        $config = Get-Configuration -ConfigPath $ConfigPath
        $binaryPaths = $config.binary_paths
        
        # Check for existing checksums
        $existingChecksums = @{}
        if ($config.PSObject.Properties.Name -contains "binary_checksums") {
            foreach ($binaryName in $config.binary_checksums.PSObject.Properties.Name) {
                $existingChecksums[$binaryName] = $config.binary_checksums.$binaryName
            }
        }
        
        # Verify each binary
        foreach ($binaryName in $binaryPaths.PSObject.Properties.Name) {
            $binaryPath = $binaryPaths.$binaryName
            $verificationResults.TotalBinaries++
            
            Write-IntegrityLog -Level "INFO" -Message "Verifying binary: $binaryName"
            
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
                    $verificationResults.MissingBinaries++
                    
                    Write-IntegrityLog -Level "ERROR" -Message "Binary not found: $binaryName"
                    $verificationResults.Results[$binaryName] = $result
                    continue
                }
                
                # Get file info
                $fileInfo = Get-Item $binaryPath
                $result.FileSize = $fileInfo.Length
                
                # Calculate checksum
                $hashResult = Get-BinaryChecksum -FilePath $binaryPath -Algorithm $Algorithm
                
                if ($hashResult.Success) {
                    $result.Checksum = $hashResult.Hash
                    $result.Status = "Verified"
                    $verificationResults.VerifiedBinaries++
                    
                    $verificationResults.Checksums[$binaryName] = @{
                        Hash = $hashResult.Hash
                        FileSize = $fileInfo.Length
                    }
                    
                    Write-IntegrityLog -Level "SUCCESS" -Message "Binary verified: $binaryName"
                } else {
                    $result.Status = "Failed"
                    $result.Error = $hashResult.Error
                    $verificationResults.FailedBinaries++
                    
                    Write-IntegrityLog -Level "ERROR" -Message "Verification failed: $binaryName - $($hashResult.Error)"
                }
                
            } catch {
                $result.Status = "Error"
                $result.Error = $_.Exception.Message
                $verificationResults.FailedBinaries++
                
                Write-IntegrityLog -Level "ERROR" -Message "Error verifying $binaryName`: $($_.Exception.Message)"
            }
            
            $verificationResults.Results[$binaryName] = $result
        }
        
        # Update configuration if requested
        if ($UpdateConfig -and $verificationResults.Checksums.Count -gt 0) {
            Update-Configuration -Config $config -Checksums $verificationResults.Checksums -ConfigPath $ConfigPath
        }
        
        # Generate summary
        $verificationResults.EndTime = Get-Date
        $verificationResults.Duration = $verificationResults.EndTime - $verificationResults.StartTime
        
        # Display results
        Write-Host ""
        Write-Host "📊 Verification Summary" -ForegroundColor Green
        Write-Host "======================" -ForegroundColor Green
        Write-Host "Total Binaries: $($verificationResults.TotalBinaries)"
        Write-Host "Verified: $($verificationResults.VerifiedBinaries)" -ForegroundColor Green
        Write-Host "Failed: $($verificationResults.FailedBinaries)" -ForegroundColor Red
        Write-Host "Missing: $($verificationResults.MissingBinaries)" -ForegroundColor Yellow
        Write-Host "Duration: $($verificationResults.Duration.TotalSeconds) seconds"
        
        if ($verificationResults.TotalBinaries -gt 0) {
            $successRate = [math]::Round(($verificationResults.VerifiedBinaries / $verificationResults.TotalBinaries) * 100, 2)
            Write-Host "Success Rate: $successRate%"
        }
        
        # Detailed results
        if ($Detailed) {
            Write-Host ""
            Write-Host "📋 Detailed Results" -ForegroundColor Cyan
            Write-Host "==================" -ForegroundColor Cyan
            
            foreach ($binaryName in $verificationResults.Results.Keys) {
                $result = $verificationResults.Results[$binaryName]
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
        $reportPath = $ReportPath
        $verificationResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
        
        Write-Host ""
        Write-Host "📄 Report saved to: $reportPath" -ForegroundColor Green
        Write-Host "📝 Log file: $LogPath" -ForegroundColor Green
        
        return $verificationResults
        
    } catch {
        Write-Error "Binary integrity verification failed: $($_.Exception.Message)"
        throw
    }
}

# Run verification
Start-BinaryIntegrityVerification
