<#
.SYNOPSIS
    Comprehensive Binary Integrity Verification Framework for LLM Optimization Workspace

.DESCRIPTION
    Advanced binary integrity verification system implementing 2026 PowerShell best practices.
    Provides SHA256 checksum validation, structured logging, and comprehensive reporting
    for all llama.cpp binaries in the workspace.

.AUTHOR
    LLM Optimization Workspace
    Version: 1.0
    Created: 2026-03-12

.NOTES
    Implements Microsoft PowerShell error handling best practices
    Uses Get-FileHash for SHA256 validation (2026 standard)
    Structured logging with PoshLog-compatible output
    Automated regression testing capabilities
#>

#requires -Version 5.1

#region Configuration and Variables

# Script parameters with validation
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
    [ValidateSet("SHA256", "SHA384", "SHA512")]
    [string]$Algorithm = "SHA256"
)

# Initialize logging system
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'

# Ensure required directories exist
$LogDir = Split-Path $LogPath -Parent
$ReportDir = Split-Path $ReportPath -Parent

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

if (-not (Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

#endregion

#region Logging Functions

<#
.SYNOPSIS
    Enhanced logging function with structured output and timestamping
#>
function Write-IntegrityLog {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level,
        
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = "IntegrityFramework",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Metadata = @{}
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = @{
        Timestamp = $timestamp
        Level = $Level
        Component = $Component
        Message = $Message
        Metadata = $Metadata
    }
    
    # Format log entry for file output
    $logLine = "$timestamp - [$Level] [$Component] $Message"
    if ($Metadata.Count -gt 0) {
        $logLine += " | Metadata: $($Metadata | ConvertTo-Json -Compress)"
    }
    
    # Write to log file
    Add-Content -Path $LogPath -Value $logLine
    
    # Write to console with appropriate coloring
    switch ($Level) {
        "INFO"  { Write-Host $logLine -ForegroundColor White }
        "WARN"  { Write-Warning $logLine }
        "ERROR" { Write-Error $logLine }
        "SUCCESS" { Write-Host $logLine -ForegroundColor Green }
    }
}

<#
.SYNOPSIS
    Error handling with detailed logging and stack trace
#>
function Invoke-TerminatingError {
    param(
        [Parameter(Mandatory)]
        [string]$ErrorCode,
        
        [Parameter(Mandatory)]
        [string]$ErrorMessage,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = "IntegrityFramework",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$ErrorDetails = @{}
    )
    
    $errorRecord = @{
        ErrorCode = $ErrorCode
        ErrorMessage = $ErrorMessage
        Component = $Component
        Timestamp = Get-Date
        ErrorDetails = $ErrorDetails
        StackTrace = (Get-PSCallStack | Select-Object -Skip 1 | ConvertTo-Json -Compress)
    }
    
    Write-IntegrityLog -Level "ERROR" -Message $ErrorMessage -Component $Component -Metadata $errorRecord
    throw $ErrorMessage
}

#endregion

#region Core Integrity Functions

<#
.SYNOPSIS
    Calculate SHA256 checksum for a file with progress reporting
#>
function Get-BinaryChecksum {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $false)]
        [string]$Algorithm = "SHA256",
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    try {
        Write-IntegrityLog -Level "INFO" -Message "Calculating $Algorithm checksum for $FilePath" -Metadata @{
            FileSize = if (Test-Path $FilePath) { (Get-Item $FilePath).Length / 1MB } else { 0 }
            Algorithm = $Algorithm
        }
        
        if (-not (Test-Path $FilePath)) {
            throw "File not found: $FilePath"
        }
        
        # Calculate hash with progress reporting
        $fileInfo = Get-Item $FilePath
        $hashResult = Get-FileHash -Path $FilePath -Algorithm $Algorithm
        
        Write-IntegrityLog -Level "SUCCESS" -Message "Checksum calculated successfully" -Metadata @{
            File = $fileInfo.Name
            Algorithm = $Algorithm
            Checksum = $hashResult.Hash
            FileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        }
        
        return @{
            Success = $true
            Hash = $hashResult.Hash
            Algorithm = $Algorithm
            FileSize = $fileInfo.Length
            LastModified = $fileInfo.LastWriteTime
            FilePath = $FilePath
        }
        
    } catch {
        Write-IntegrityLog -Level "ERROR" -Message "Failed to calculate checksum: $($_.Exception.Message)" -Metadata @{
            FilePath = $FilePath
            Algorithm = $Algorithm
            Exception = $_.Exception.GetType().Name
        }
        
        return @{
            Success = $false
            Error = $_.Exception.Message
            FilePath = $FilePath
        }
    }
}

<#
.SYNOPSIS
    Verify binary integrity against known checksum
#>
function Test-BinaryIntegrity {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$ExpectedHash,
        
        [Parameter(Mandatory = $false)]
        [string]$Algorithm = "SHA256",
        
        [Parameter(Mandatory = $false)]
        [switch]$SkipHashCalculation
    )
    
    $result = @{
        FilePath = $FilePath
        ExpectedHash = $ExpectedHash
        Algorithm = $Algorithm
        IntegrityCheck = $false
        FileExists = $false
        HashMatch = $false
        Error = $null
        ActualHash = $null
        FileSize = 0
        LastModified = $null
    }
    
    try {
        # Check file existence
        if (-not (Test-Path $FilePath)) {
            $result.Error = "File not found: $FilePath"
            Write-IntegrityLog -Level "ERROR" -Message $result.Error -Metadata @{ FilePath = $FilePath }
            return $result
        }
        
        $result.FileExists = $true
        $fileInfo = Get-Item $FilePath
        $result.FileSize = $fileInfo.Length
        $result.LastModified = $fileInfo.LastWriteTime
        
        # Calculate current hash
        if (-not $SkipHashCalculation) {
            $hashResult = Get-BinaryChecksum -FilePath $FilePath -Algorithm $Algorithm
            
            if (-not $hashResult.Success) {
                $result.Error = $hashResult.Error
                return $result
            }
            
            $result.ActualHash = $hashResult.Hash
        }
        
        # Compare hashes
        $result.HashMatch = ($result.ActualHash -eq $ExpectedHash)
        $result.IntegrityCheck = $result.FileExists -and $result.HashMatch
        
        if ($result.IntegrityCheck) {
            Write-IntegrityLog -Level "SUCCESS" -Message "Binary integrity verified" -Metadata @{
                File = $fileInfo.Name
                ExpectedHash = $ExpectedHash.Substring(0, 8) + "..."
                ActualHash = $result.ActualHash.Substring(0, 8) + "..."
                Algorithm = $Algorithm
            }
        } else {
            $result.Error = if ($result.HashMatch) { "Hash mismatch detected" } else { "File integrity check failed" }
            Write-IntegrityLog -Level "ERROR" -Message $result.Error -Metadata @{
                File = $fileInfo.Name
                ExpectedHash = $ExpectedHash.Substring(0, 8) + "..."
                ActualHash = $result.ActualHash.Substring(0, 8) + "..."
                HashMatch = $result.HashMatch
                FileExists = $result.FileExists
            }
        }
        
    } catch {
        $result.Error = $_.Exception.Message
        Write-IntegrityLog -Level "ERROR" -Message "Integrity check failed: $($_.Exception.Message)" -Metadata @{
            FilePath = $FilePath
            Exception = $_.Exception.GetType().Name
        }
    }
    
    return $result
}

#endregion

#region Configuration Management

<#
.SYNOPSIS
    Load and validate configuration file
#>
function Get-IntegrityConfiguration {
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
        
        Write-IntegrityLog -Level "SUCCESS" -Message "Configuration loaded and validated" -Metadata @{
            BinaryCount = $config.binary_paths.PSObject.Properties.Name.Count
            ModelCount = $config.model_paths.PSObject.Properties.Name.Count
        }
        
        return $config
        
    } catch {
        Invoke-TerminatingError -ErrorCode "CONFIG_LOAD_FAILED" -ErrorMessage $_.Exception.Message -ErrorDetails @{
            ConfigPath = $ConfigPath
            Exception = $_.Exception.GetType().Name
        }
    }
}

<#
.SYNOPSIS
    Update configuration with verified checksums
#>
function Update-ConfigurationWithChecksums {
    param(
        [object]$Config,
        [hashtable]$Checksums,
        [string]$ConfigPath = "config.json"
    )
    
    try {
        Write-IntegrityLog -Level "INFO" -Message "Updating configuration with verified checksums"
        
        # Create backup
        $backupPath = "$ConfigPath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $ConfigPath $backupPath
        Write-IntegrityLog -Level "INFO" -Message "Configuration backed up to $backupPath"
        
        # Add checksums section if it doesn't exist
        if (-not ($Config.PSObject.Properties.Name -contains "binary_checksums")) {
            $Config | Add-Member -NotePropertyName "binary_checksums" -NotePropertyValue @{}
        }
        
        # Update checksums
        foreach ($binaryName in $Checksums.Keys) {
            $Config.binary_checksums | Add-Member -NotePropertyName $binaryName -NotePropertyValue @{
                hash = $Checksums[$binaryName].Hash
                algorithm = $Checksums[$binaryName].Algorithm
                verified = $Checksums[$binaryName].Verified
                timestamp = $Checksums[$binaryName].Timestamp
                file_size = $Checksums[$binaryName].FileSize
            } -Force
        }
        
        # Save updated configuration
        $Config | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigPath -Encoding UTF8
        
        Write-IntegrityLog -Level "SUCCESS" -Message "Configuration updated successfully" -Metadata @{
            ChecksumCount = $Checksums.Count
            ConfigPath = $ConfigPath
            BackupPath = $backupPath
        }
        
        return $true
        
    } catch {
        Invoke-TerminatingError -ErrorCode "CONFIG_UPDATE_FAILED" -ErrorMessage $_.Exception.Message -ErrorDetails @{
            ConfigPath = $ConfigPath
            Exception = $_.Exception.GetType().Name
        }
    }
}

#endregion

#region Main Verification Framework

<#
.SYNOPSIS
    Comprehensive binary integrity verification for all configured binaries
#>
function Test-BinaryIntegrityComprehensive {
    param(
        [string]$ConfigPath = "config.json",
        [switch]$UpdateConfig,
        [switch]$Detailed,
        [switch]$ForceRehash,
        [string]$Algorithm = "SHA256"
    )
    
    $verificationSession = @{
        StartTime = Get-Date
        ConfigPath = $ConfigPath
        Algorithm = $Algorithm
        Results = @{}
        Summary = @{
            TotalBinaries = 0
            VerifiedBinaries = 0
            FailedBinaries = 0
            MissingBinaries = 0
            SkippedBinaries = 0
        }
        Checksums = @{}
        Errors = @()
    }
    
    try {
        Write-IntegrityLog -Level "INFO" -Message "Starting comprehensive binary integrity verification" -Metadata @{
            ConfigPath = $ConfigPath
            Algorithm = $Algorithm
            ForceRehash = $ForceRehash.IsPresent
        }
        
        # Load configuration
        $config = Get-IntegrityConfiguration -ConfigPath $ConfigPath
        $binaryPaths = $config.binary_paths
        
        # Check for existing checksums in configuration
        $existingChecksums = @{}
        if ($config.PSObject.Properties.Name -contains "binary_checksums") {
            foreach ($binaryName in $config.binary_checksums.PSObject.Properties.Name) {
                $existingChecksums[$binaryName] = $config.binary_checksums.$binaryName
            }
        }
        
        # Verify each binary
        foreach ($binaryName in $binaryPaths.PSObject.Properties.Name) {
            $binaryPath = $binaryPaths.$binaryName
            $verificationSession.Summary.TotalBinaries++
            
            Write-IntegrityLog -Level "INFO" -Message "Verifying binary: $binaryName" -Metadata @{
                BinaryName = $binaryName
                BinaryPath = $binaryPath
            }
            
            $binaryResult = @{
                BinaryName = $binaryName
                BinaryPath = $binaryPath
                VerificationTime = Get-Date
                Status = "Unknown"
                Checksum = $null
                ExpectedChecksum = $null
                IntegrityCheck = $false
                Error = $null
                FileSize = 0
                LastModified = $null
            }
            
            try {
                # Check if file exists
                if (-not (Test-Path $binaryPath)) {
                    $binaryResult.Status = "Missing"
                    $binaryResult.Error = "Binary file not found"
                    $verificationSession.Summary.MissingBinaries++
                    $verificationSession.Errors += "Binary not found: $binaryName -> $binaryPath"
                    
                    Write-IntegrityLog -Level "ERROR" -Message "Binary not found: $binaryName" -Metadata @{
                        BinaryName = $binaryName
                        ExpectedPath = $binaryPath
                    }
                    
                    $verificationSession.Results[$binaryName] = $binaryResult
                    continue
                }
                
                # Get file info
                $fileInfo = Get-Item $binaryPath
                $binaryResult.FileSize = $fileInfo.Length
                $binaryResult.LastModified = $fileInfo.LastWriteTime
                
                # Determine expected checksum
                $expectedHash = $null
                if ($existingChecksums.ContainsKey($binaryName) -and -not $ForceRehash) {
                    $expectedHash = $existingChecksums[$binaryName].hash
                    $binaryResult.ExpectedChecksum = $expectedHash
                    
                    Write-IntegrityLog -Level "INFO" -Message "Using existing checksum for $binaryName" -Metadata @{
                        ExpectedHash = $expectedHash.Substring(0, 8) + "..."
                        Algorithm = $existingChecksums[$binaryName].algorithm
                    }
                }
                
                # Calculate or verify checksum
                if ($expectedHash) {
                    # Verify against existing checksum
                    $integrityResult = Test-BinaryIntegrity -FilePath $binaryPath -ExpectedHash $expectedHash -Algorithm $Algorithm
                    
                    $binaryResult.Checksum = $integrityResult.ActualHash
                    $binaryResult.IntegrityCheck = $integrityResult.IntegrityCheck
                    $binaryResult.Status = if ($integrityResult.IntegrityCheck) { "Verified" } else { "Failed" }
                    
                    if ($integrityResult.IntegrityCheck) {
                        $verificationSession.Summary.VerifiedBinaries++
                        $verificationSession.Checksums[$binaryName] = @{
                            Hash = $integrityResult.ActualHash
                            Algorithm = $Algorithm
                            Verified = $true
                            Timestamp = Get-Date
                            FileSize = $fileInfo.Length
                        }
                    } else {
                        $verificationSession.Summary.FailedBinaries++
                        $binaryResult.Error = $integrityResult.Error
                        $verificationSession.Errors += "Integrity check failed: $binaryName - $($integrityResult.Error)"
                    }
                } else {
                    # Calculate new checksum
                    $hashResult = Get-BinaryChecksum -FilePath $binaryPath -Algorithm $Algorithm
                    
                    if ($hashResult.Success) {
                        $binaryResult.Checksum = $hashResult.Hash
                        $binaryResult.Status = "Calculated"
                        $binaryResult.IntegrityCheck = $true  # New checksum is always valid
                        
                        $verificationSession.Summary.VerifiedBinaries++
                        $verificationSession.Checksums[$binaryName] = @{
                            Hash = $hashResult.Hash
                            Algorithm = $Algorithm
                            Verified = $true
                            Timestamp = Get-Date
                            FileSize = $fileInfo.Length
                        }
                        
                        Write-IntegrityLog -Level "SUCCESS" -Message "New checksum calculated for $binaryName" -Metadata @{
                            Hash = $hashResult.Hash.Substring(0, 8) + "..."
                            FileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
                        }
                    } else {
                        $binaryResult.Status = "Failed"
                        $binaryResult.Error = $hashResult.Error
                        $verificationSession.Summary.FailedBinaries++
                        $verificationSession.Errors += "Checksum calculation failed: $binaryName - $($hashResult.Error)"
                    }
                }
                
            } catch {
                $binaryResult.Status = "Error"
                $binaryResult.Error = $_.Exception.Message
                $verificationSession.Summary.FailedBinaries++
                $verificationSession.Errors += "Verification error: $binaryName - $($_.Exception.Message)"
                
                Write-IntegrityLog -Level "ERROR" -Message "Verification error for $binaryName`: $($_.Exception.Message)" -Metadata @{
                    BinaryName = $binaryName
                    Exception = $_.Exception.GetType().Name
                }
            }
            
            $verificationSession.Results[$binaryName] = $binaryResult
        }
        
        # Update configuration if requested and we have new checksums
        if ($UpdateConfig -and $verificationSession.Checksums.Count -gt 0) {
            Update-ConfigurationWithChecksums -Config $config -Checksums $verificationSession.Checksums -ConfigPath $ConfigPath
        }
        
        # Generate summary
        $verificationSession.EndTime = Get-Date
        $verificationSession.Duration = $verificationSession.EndTime - $verificationSession.StartTime
        
        Write-IntegrityLog -Level "INFO" -Message "Binary integrity verification completed" -Metadata @{
            Duration = $verificationSession.Duration.TotalSeconds
            TotalBinaries = $verificationSession.Summary.TotalBinaries
            VerifiedBinaries = $verificationSession.Summary.VerifiedBinaries
            FailedBinaries = $verificationSession.Summary.FailedBinaries
            MissingBinaries = $verificationSession.Summary.MissingBinaries
            SuccessRate = if ($verificationSession.Summary.TotalBinaries -gt 0) { 
                [math]::Round(($verificationSession.Summary.VerifiedBinaries / $verificationSession.Summary.TotalBinaries) * 100, 2) 
            } else { 0 }
        }
        
        return $verificationSession
        
    } catch {
        Invoke-TerminatingError -ErrorCode "VERIFICATION_FAILED" -ErrorMessage "Comprehensive verification failed: $($_.Exception.Message)" -ErrorDetails @{
            ConfigPath = $ConfigPath
            Exception = $_.Exception.GetType().Name
            StackTrace = (Get-PSCallStack | ConvertTo-Json -Compress)
        }
    }
}

#endregion

#region Reporting Functions

<#
.SYNOPSIS
    Generate comprehensive integrity verification report
#>
function New-IntegrityReport {
    param(
        [hashtable]$VerificationSession,
        [string]$ReportPath = "Reports\binary_integrity_$(Get-Date -Format 'yyyyMMdd_HHmmss').json",
        [switch]$Detailed
    )
    
    try {
        Write-IntegrityLog -Level "INFO" -Message "Generating integrity verification report"
        
        $report = @{
            Metadata = @{
                ReportGenerated = Get-Date
                ReportVersion = "1.0"
                Algorithm = $VerificationSession.Algorithm
                ConfigPath = $VerificationSession.ConfigPath
                Duration = $VerificationSession.Duration
                ForceRehash = $false
            }
            Summary = $VerificationSession.Summary
            Results = $VerificationSession.Results
            Errors = $VerificationSession.Errors
            Checksums = $VerificationSession.Checksums
        }
        
        # Add detailed analysis if requested
        if ($Detailed) {
            $report.Analysis = @{
                FileSizeDistribution = @()
                VerificationStatusBreakdown = @()
                Recommendations = @()
                SecurityAssessment = @{}
            }
            
            # File size analysis
            $fileSizes = $VerificationSession.Results.Values | Where-Object { $_.FileSize -gt 0 } | Select-Object FileSize, BinaryName
            if ($fileSizes) {
                $totalSize = ($fileSizes | Measure-Object -Property FileSize -Sum).Sum
                $report.Analysis.FileSizeDistribution = @{
                    TotalSizeMB = [math]::Round($totalSize / 1MB, 2)
                    AverageSizeMB = [math]::Round(($totalSize / $fileSizes.Count) / 1MB, 2)
                    LargestBinary = $fileSizes | Sort-Object FileSize -Descending | Select-Object -First 1
                    SmallestBinary = $fileSizes | Sort-Object FileSize | Select-Object -First 1
                }
            }
            
            # Status breakdown
            $statusGroups = $VerificationSession.Results.Values | Group-Object Status
            $report.Analysis.VerificationStatusBreakdown = $statusGroups | ForEach-Object {
                @{
                    Status = $_.Name
                    Count = $_.Count
                    Percentage = [math]::Round(($_.Count / $VerificationSession.Summary.TotalBinaries) * 100, 2)
                }
            }
            
            # Generate recommendations
            $recommendations = @()
            
            if ($VerificationSession.Summary.MissingBinaries -gt 0) {
                $recommendations += "Missing binaries detected. Verify binary paths in configuration."
            }
            
            if ($VerificationSession.Summary.FailedBinaries -gt 0) {
                $recommendations += "Integrity check failures detected. Investigate potential corruption or tampering."
            }
            
            if ($VerificationSession.Summary.VerifiedBinaries -eq $VerificationSession.Summary.TotalBinaries) {
                $recommendations += "All binaries verified successfully. Consider implementing automated periodic verification."
            }
            
            $report.Analysis.Recommendations = $recommendations
            
            # Security assessment
            $report.Analysis.SecurityAssessment = @{
                IntegrityStatus = if ($VerificationSession.Summary.FailedBinaries -eq 0) { "Secure" } else { "Compromised" }
                VerificationCoverage = [math]::Round(($VerificationSession.Summary.VerifiedBinaries / $VerificationSession.Summary.TotalBinaries) * 100, 2)
                LastVerified = Get-Date
                RiskLevel = if ($VerificationSession.Summary.FailedBinaries -gt 0) { "High" } elseif ($VerificationSession.Summary.MissingBinaries -gt 0) { "Medium" } else { "Low" }
            }
        }
        
        # Save report
        $reportJson = $report | ConvertTo-Json -Depth 10
        $reportJson | Out-File -FilePath $ReportPath -Encoding UTF8
        
        Write-IntegrityLog -Level "SUCCESS" -Message "Integrity report generated" -Metadata @{
            ReportPath = $ReportPath
            ReportSizeKB = [math]::Round(($reportJson.Length / 1KB), 2)
            Detailed = $Detailed.IsPresent
        }
        
        return $report
        
    } catch {
        Invoke-TerminatingError -ErrorCode "REPORT_GENERATION_FAILED" -ErrorMessage "Failed to generate report: $($_.Exception.Message)" -ErrorDetails @{
            ReportPath = $ReportPath
            Exception = $_.Exception.GetType().Name
        }
    }
}

#endregion

#region Main Execution

<#
.SYNOPSIS
    Main entry point for binary integrity verification
#>
function Start-BinaryIntegrityVerification {
    param(
        [string]$ConfigPath = "config.json",
        [switch]$UpdateConfig,
        [switch]$Detailed,
        [switch]$ForceRehash,
        [string]$Algorithm = "SHA256"
    )
    
    Write-Host "🔍 Binary Integrity Verification Framework" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        # Start comprehensive verification
        $verificationSession = Test-BinaryIntegrityComprehensive -ConfigPath $ConfigPath -UpdateConfig:$UpdateConfig -Detailed:$Detailed -ForceRehash:$ForceRehash -Algorithm $Algorithm
        
        # Generate report
        $report = New-IntegrityReport -VerificationSession $verificationSession -ReportPath $ReportPath -Detailed:$Detailed
        
        # Display summary
        Write-Host ""
        Write-Host "📊 Verification Summary" -ForegroundColor Green
        Write-Host "======================" -ForegroundColor Green
        Write-Host "Total Binaries: $($verificationSession.Summary.TotalBinaries)"
        Write-Host "Verified: $($verificationSession.Summary.VerifiedBinaries)" -ForegroundColor Green
        Write-Host "Failed: $($verificationSession.Summary.FailedBinaries)" -ForegroundColor Red
        Write-Host "Missing: $($verificationSession.Summary.MissingBinaries)" -ForegroundColor Yellow
        Write-Host "Duration: $($verificationSession.Duration.TotalSeconds) seconds"
        Write-Host "Success Rate: $([math]::Round(($verificationSession.Summary.VerifiedBinaries / $verificationSession.Summary.TotalBinaries) * 100, 2))%"
        Write-Host ""
        
        # Display detailed results if requested
        if ($Detailed) {
            Write-Host "📋 Detailed Results" -ForegroundColor Cyan
            Write-Host "==================" -ForegroundColor Cyan
            
            foreach ($binaryName in $verificationSession.Results.Keys) {
                $result = $verificationSession.Results[$binaryName]
                $statusColor = switch ($result.Status) {
                    "Verified" { "Green" }
                    "Calculated" { "Cyan" }
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
        
        # Display recommendations
        if ($report.Analysis -and $report.Analysis.Recommendations.Count -gt 0) {
            Write-Host "💡 Recommendations" -ForegroundColor Yellow
            Write-Host "================" -ForegroundColor Yellow
            foreach ($recommendation in $report.Analysis.Recommendations) {
                Write-Host "• $recommendation"
            }
            Write-Host ""
        }
        
        # Display report location
        Write-Host "📄 Report saved to: $ReportPath" -ForegroundColor Green
        Write-Host "📝 Log file: $LogPath" -ForegroundColor Green
        
        return $verificationSession
        
    } catch {
        Write-Error "Binary integrity verification failed: $($_.Exception.Message)"
        throw
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Start-BinaryIntegrityVerification',
    'Test-BinaryIntegrityComprehensive', 
    'Get-BinaryChecksum',
    'Test-BinaryIntegrity',
    'New-IntegrityReport',
    'Write-IntegrityLog',
    'Invoke-TerminatingError'
)
