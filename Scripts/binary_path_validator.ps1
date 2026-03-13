# Comprehensive Binary Path Validation Framework
# 2026 Research-based PowerShell automation for LLM workspace
# Validates and corrects binary paths in config.json with modern best practices

#region Module Configuration

# Set strict error handling for 2026 best practices
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Import required modules
if (-not (Get-Module -Name 'Microsoft.PowerShell.Utility' -ListAvailable)) {
    throw "Required PowerShell module not available"
}

#endregion

#region Core Validation Functions

function Test-BinaryPathsComprehensive {
    <#
    .SYNOPSIS
        Comprehensive binary path validation framework with 2026 best practices
    .DESCRIPTION
        Tests all binary paths in config.json with existence, functionality, and help command validation
        Implements automated path correction and comprehensive error reporting
    .PARAMETER ConfigPath
        Path to config.json file (default: ".\config.json")
    .PARAMETER UpdateConfig
        Switch to automatically update config.json with corrected paths
    .PARAMETER Detailed
        Switch to generate detailed validation reports
    .PARAMETER LogPath
        Path for validation log file (default: "Logs\binary_validation.log")
    .EXAMPLE
        Test-BinaryPathsComprehensive -UpdateConfig -Detailed
    .OUTPUTS
        Hashtable with comprehensive validation results
    #>
    
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath = ".\config.json",
        
        [Parameter(Mandatory=$false)]
        [switch]$UpdateConfig,
        
        [Parameter(Mandatory=$false)]
        [switch]$Detailed,
        
        [Parameter(Mandatory=$false)]
        [string]$LogPath = "Logs\binary_validation.log"
    )
    
    # Initialize validation results structure
    $validationResults = @{
        ConfigValid = $false
        BinaryTests = @{}
        PathCorrections = @{}
        Errors = @()
        Warnings = @()
        UpdatedPaths = @{}
        ValidationTimestamp = Get-Date
        TotalBinaries = 0
        ValidBinaries = 0
        CorrectedPaths = 0
    }
    
    try {
        Write-Host "=== Comprehensive Binary Path Validation ===" -ForegroundColor Cyan
        Write-Host "Config: $ConfigPath" -ForegroundColor Gray
        Write-Host "Timestamp: $($validationResults.ValidationTimestamp)" -ForegroundColor Gray
        Write-Host ""
        
        # Step 1: Validate JSON structure using 2026 Test-Json cmdlet
        Write-Host "Step 1: Validating JSON structure..." -ForegroundColor Yellow
        $jsonValidation = Test-JsonConfig -ConfigPath $ConfigPath
        $validationResults.ConfigValid = $jsonValidation.Valid
        
        if (-not $jsonValidation.Valid) {
            $validationResults.Errors += $jsonValidation.Errors
            Write-Host "❌ JSON validation failed:" -ForegroundColor Red
            $jsonValidation.Errors | ForEach-Object { Write-Host "  • $_" -ForegroundColor Gray }
            return $validationResults
        }
        
        Write-Host "✅ JSON structure validated" -ForegroundColor Green
        
        # Step 2: Load and validate binary paths
        Write-Host "Step 2: Loading binary paths from config..." -ForegroundColor Yellow
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $binaryPaths = $config.binary_paths
        
        if (-not $binaryPaths) {
            throw "binary_paths section not found in config.json"
        }
        
        $validationResults.TotalBinaries = $binaryPaths.PSObject.Properties.Count
        
        foreach ($binaryName in $binaryPaths.PSObject.Properties.Name) {
            $binaryPath = $binaryPaths.$binaryName
            Write-Host "Testing binary: $binaryName -> $binaryPath" -ForegroundColor Cyan
            
            # Test binary comprehensively
            $result = Test-SingleBinaryComprehensive -BinaryName $binaryName -BinaryPath $binaryPath
            $validationResults.BinaryTests[$binaryName] = $result
            
            if ($result.Valid) {
                $validationResults.ValidBinaries++
                Write-Host "✅ $binaryName - Valid" -ForegroundColor Green
            } else {
                Write-Host "❌ $binaryName - Invalid: $($result.ErrorMessage)" -ForegroundColor Red
                
                # Attempt path correction
                Write-Host "  🔍 Searching for corrected path..." -ForegroundColor Yellow
                $correction = Find-BinaryPathCorrection -BinaryName $binaryName -OriginalPath $binaryPath
                
                if ($correction.Found) {
                    $validationResults.PathCorrections[$binaryName] = $correction
                    $validationResults.UpdatedPaths[$binaryName] = $correction.CorrectedPath
                    $validationResults.CorrectedPaths++
                    
                    Write-Host "  ✅ Found: $($correction.CorrectedPath)" -ForegroundColor Green
                    
                    # Test corrected path
                    $correctedResult = Test-SingleBinaryComprehensive -BinaryName $binaryName -BinaryPath $correction.CorrectedPath
                    $validationResults.BinaryTests["${binaryName}_corrected"] = $correctedResult
                    
                    if ($correctedResult.Valid) {
                        Write-Host "  ✅ Corrected path validated" -ForegroundColor Green
                    } else {
                        Write-Host "  ⚠️ Corrected path failed: $($correctedResult.ErrorMessage)" -ForegroundColor Yellow
                    }
                } else {
                    $validationResults.Errors += "Failed to find valid path for $binaryName"
                    Write-Host "  ❌ No valid path found" -ForegroundColor Red
                }
            }
            
            Write-Host ""
        }
        
        # Step 3: Update config if requested and corrections found
        if ($UpdateConfig -and $validationResults.PathCorrections.Count -gt 0) {
            Write-Host "Step 3: Updating config.json with corrected paths..." -ForegroundColor Yellow
            $updateResult = Update-ConfigPaths -ConfigPath $ConfigPath -Corrections $validationResults.UpdatedPaths
            
            if ($updateResult.Success) {
                Write-Host "✅ Config.json updated successfully" -ForegroundColor Green
                Write-Host "  Backup created: $($updateResult.BackupPath)" -ForegroundColor Gray
            } else {
                Write-Host "❌ Config update failed: $($updateResult.ErrorMessage)" -ForegroundColor Red
                $validationResults.Errors += $updateResult.ErrorMessage
            }
        } else {
            Write-Host "Step 3: Config update skipped" -ForegroundColor Gray
        }
        
        # Step 4: Generate detailed report if requested
        if ($Detailed) {
            Write-Host "Step 4: Generating detailed validation report..." -ForegroundColor Yellow
            $reportPath = "Reports\binary_validation_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"
            
            # Ensure Reports directory exists
            $reportDir = Split-Path $reportPath -Parent
            if (-not (Test-Path $reportDir)) {
                New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
            }
            
            $validationResults | Export-Clixml -Path $reportPath
            Write-Host "✅ Detailed report saved: $reportPath" -ForegroundColor Green
        }
        
        # Step 5: Display summary
        Write-Host ""
        Write-Host "=== Validation Summary ===" -ForegroundColor Magenta
        Write-Host "Total Binaries: $($validationResults.TotalBinaries)" -ForegroundColor White
        Write-Host "Valid Binaries: $($validationResults.ValidBinaries)" -ForegroundColor Green
        Write-Host "Corrected Paths: $($validationResults.CorrectedPaths)" -ForegroundColor Yellow
        Write-Host "Errors: $($validationResults.Errors.Count)" -ForegroundColor $(if($validationResults.Errors.Count -eq 0) {"Green"} else {"Red"})
        Write-Host "Warnings: $($validationResults.Warnings.Count)" -ForegroundColor Yellow
        
    } catch {
        $validationResults.Errors += "Validation framework error: $($_.Exception.Message)"
        Write-Host "❌ Critical validation error: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        # Step 6: Log results
        Write-ValidationLog -Results $validationResults -LogPath $LogPath
    }
    
    return $validationResults
}

function Test-JsonConfig {
    <#
    .SYNOPSIS
        JSON schema validation for config.json using 2026 Test-Json cmdlet
    .DESCRIPTION
        Validates JSON structure and required sections for config.json
        Uses modern PowerShell Test-Json cmdlet with schema validation
    #>
    
    param([string]$ConfigPath)
    
    $result = @{
        Valid = $false
        Errors = @()
        Warnings = @()
    }
    
    try {
        # Test basic JSON structure using 2026 Test-Json cmdlet
        if (-not (Test-Path $ConfigPath)) {
            $result.Errors += "Config file not found: $ConfigPath"
            return $result
        }
        
        $jsonContent = Get-Content $ConfigPath -Raw
        
        # Use Test-Json cmdlet for syntax validation (2026 best practice)
        if (-not (Test-Json $jsonContent)) {
            $result.Errors += "Invalid JSON syntax in $ConfigPath"
            return $result
        }
        
        # Test required structure
        $config = $jsonContent | ConvertFrom-Json
        $requiredSections = @("model_paths", "binary_paths", "optimization_defaults", "hardware_config")
        
        foreach ($section in $requiredSections) {
            if (-not ($config.PSObject.Properties.Name -contains $section)) {
                $result.Errors += "Missing required section: $section"
            }
        }
        
        # Test binary_paths structure
        if ($config.binary_paths) {
            $requiredBinaries = @("main", "server", "quantize")
            foreach ($binary in $requiredBinaries) {
                if (-not ($config.binary_paths.PSObject.Properties.Name -contains $binary)) {
                    $result.Warnings += "Recommended binary missing: $binary"
                }
            }
            
            # Validate path formats
            foreach ($binaryName in $config.binary_paths.PSObject.Properties.Name) {
                $binaryPath = $config.binary_paths.$binaryName
                if ($binaryPath -notmatch '\\.exe$') {
                    $result.Warnings += "Binary path may not point to executable: $binaryName -> $binaryPath"
                }
            }
        }
        
        $result.Valid = $result.Errors.Count -eq 0
        
    } catch {
        $result.Errors += "JSON validation error: $($_.Exception.Message)"
    }
    
    return $result
}

function Test-SingleBinaryComprehensive {
    <#
    .SYNOPSIS
        Comprehensive single binary testing with existence, executability, and help testing
    .DESCRIPTION
        Tests individual binary files for existence, executability, and help command functionality
        Implements 2026 best practices for binary validation
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [string]$BinaryName,
        
        [Parameter(Mandatory=$true)]
        [string]$BinaryPath,
        
        [Parameter(Mandatory=$false)]
        [int]$Timeout = 30
    )
    
    $result = @{
        Valid = $false
        BinaryName = $BinaryName
        OriginalPath = $BinaryPath
        Exists = $false
        Executable = $false
        HelpWorks = $false
        Version = $null
        Size = 0
        ErrorMessage = $null
        ResponseTime = 0
        TestTimestamp = Get-Date
    }
    
    try {
        # Test 1: File existence
        if (-not (Test-Path $BinaryPath -PathType Leaf)) {
            $result.ErrorMessage = "File not found: $BinaryPath"
            return $result
        }
        $result.Exists = $true
        
        # Test 2: File properties
        $fileInfo = Get-Item $BinaryPath
        $result.Size = $fileInfo.Length / 1MB
        
        # Test 3: Executability (basic execution test)
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Try to execute binary with --help flag
        $process = Start-Process -FilePath $BinaryPath -ArgumentList "--help" -PassThru -NoNewWindow -RedirectStandardOutput "NUL" -RedirectStandardError "NUL" -ErrorAction Stop
        
        # Wait for process to complete or timeout
        $process.WaitForExit($Timeout * 1000) | Out-Null
        $stopwatch.Stop()
        
        $result.ResponseTime = $stopwatch.ElapsedMilliseconds
        $result.Executable = $true
        
        # Test 4: Help command validation
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 1) {
            # Exit code 0 or 1 usually indicates help was displayed
            $result.HelpWorks = $true
        } else {
            # Try alternative help flags
            foreach ($helpFlag in @("-h", "--usage", "-?", "/help", "/h")) {
                $testProcess = Start-Process -FilePath $BinaryPath -ArgumentList $helpFlag -PassThru -NoNewWindow -RedirectStandardOutput "NUL" -RedirectStandardError "NUL" -ErrorAction Stop
                $testProcess.WaitForExit(5000) | Out-Null
                
                if ($testProcess.ExitCode -eq 0 -or $testProcess.ExitCode -eq 1) {
                    $result.HelpWorks = $true
                    break
                }
            }
        }
        
        # Test 5: Version extraction (if possible)
        try {
            $versionProcess = Start-Process -FilePath $BinaryPath -ArgumentList "--version" -PassThru -NoNewWindow -RedirectStandardOutput "temp_version.txt" -RedirectStandardError "NUL" -ErrorAction Stop
            $versionProcess.WaitForExit(5000) | Out-Null
            
            if (Test-Path "temp_version.txt") {
                $versionOutput = Get-Content "temp_version.txt" -Raw
                if ($versionOutput -match '(\d+\.\d+(\.\d+)?)') {
                    $result.Version = $matches[1]
                }
                Remove-Item "temp_version.txt" -Force -ErrorAction SilentlyContinue
            }
        } catch {
            # Version extraction is optional, don't fail if it doesn't work
        }
        
        # Determine overall validity
        $result.Valid = $result.Exists -and $result.Executable
        
        if (-not $result.HelpWorks) {
            $result.Warnings = @("Help command not working for $BinaryName")
        }
        
    } catch {
        $result.ErrorMessage = $_.Exception.Message
    }
    
    return $result
}

function Find-BinaryPathCorrection {
    <#
    .SYNOPSIS
        Automated path correction and normalization system with intelligent search
    .DESCRIPTION
        Searches for corrected binary paths using multiple search strategies
        Implements 2026 best practices for path normalization and correction
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [string]$BinaryName,
        
        [Parameter(Mandatory=$true)]
        [string]$OriginalPath
    )
    
    $result = @{
        Found = $false
        BinaryName = $BinaryName
        OriginalPath = $OriginalPath
        CorrectedPath = $null
        SearchStrategy = $null
        SearchTime = 0
    }
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        # Strategy 1: Check common binary names and locations
        $binaryMappings = @{
            "main" = @("main.exe", "llama-cli.exe", "llama.exe")
            "server" = @("llama-server.exe", "server.exe")
            "quantize" = @("llama-quantize.exe", "quantize.exe")
            "avx2" = @("main.exe", "llama-cli.exe")
        }
        
        $searchLocations = @(
            ".\Tools\bin",
            ".\Tools\bin-avx2", 
            ".\bin",
            ".\bin-avx2",
            ".",
            "..\Tools\bin",
            "..\Tools\bin-avx2"
        )
        
        # Strategy 2: Try exact binary name mappings
        if ($binaryMappings.ContainsKey($BinaryName)) {
            foreach ($binaryVariant in $binaryMappings[$BinaryName]) {
                foreach ($location in $searchLocations) {
                    $testPath = Join-Path $location $binaryVariant
                    if (Test-Path $testPath -PathType Leaf) {
                        # Test if this binary actually works
                        $testResult = Test-SingleBinaryComprehensive -BinaryName $BinaryName -BinaryPath $testPath -Timeout 10
                        if ($testResult.Valid) {
                            $result.Found = $true
                            $result.CorrectedPath = $testPath
                            $result.SearchStrategy = "Binary Mapping"
                            $stopwatch.Stop()
                            $result.SearchTime = $stopwatch.ElapsedMilliseconds
                            return $result
                        }
                    }
                }
            }
        }
        
        # Strategy 3: Search Tools/bin directory for any executable with similar name
        $toolsBinPath = ".\Tools\bin"
        if (Test-Path $toolsBinPath) {
            $allBinaries = Get-ChildItem -Path $toolsBinPath -Filter "*.exe" -File
            
            # Look for partial matches
            foreach ($binary in $allBinaries) {
                if ($binary.Name -like "*$BinaryName*" -or $binary.Name -like "*main*" -or $binary.Name -like "*llama*") {
                    $testResult = Test-SingleBinaryComprehensive -BinaryName $BinaryName -BinaryPath $binary.FullName -Timeout 10
                    if ($testResult.Valid) {
                        $result.Found = $true
                        $result.CorrectedPath = $binary.FullName
                        $result.SearchStrategy = "Pattern Search"
                        $stopwatch.Stop()
                        $result.SearchTime = $stopwatch.ElapsedMilliseconds
                        return $result
                    }
                }
            }
        }
        
        # Strategy 4: Try to extract original filename and search for it
        $originalFileName = Split-Path $OriginalPath -Leaf
        if ($originalFileName) {
            foreach ($location in $searchLocations) {
                $testPath = Join-Path $location $originalFileName
                if (Test-Path $testPath -PathType Leaf) {
                    $testResult = Test-SingleBinaryComprehensive -BinaryName $BinaryName -BinaryPath $testPath -Timeout 10
                    if ($testResult.Valid) {
                        $result.Found = $true
                        $result.CorrectedPath = $testPath
                        $result.SearchStrategy = "Original Filename"
                        $stopwatch.Stop()
                        $result.SearchTime = $stopwatch.ElapsedMilliseconds
                        return $result
                    }
                }
            }
        }
        
    } catch {
        $result.ErrorMessage = $_.Exception.Message
    } finally {
        $stopwatch.Stop()
        $result.SearchTime = $stopwatch.ElapsedMilliseconds
    }
    
    return $result
}

function Update-ConfigPaths {
    <#
    .SYNOPSIS
        Safe configuration updates with automated backup procedures
    .DESCRIPTION
        Updates config.json with corrected binary paths using safe backup procedures
        Implements 2026 best practices for configuration management
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Corrections
    )
    
    $result = @{
        Success = $false
        BackupPath = $null
        UpdatedPaths = @()
        Error = $null
    }
    
    try {
        # Create backup before modification
        $backupPath = "$ConfigPath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item -Path $ConfigPath -Destination $backupPath -Force
        $result.BackupPath = $backupPath
        
        # Load config
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        
        # Update paths
        foreach ($binaryName in $Corrections.Keys) {
            $newPath = $Corrections[$binaryName]
            $config.binary_paths.$binaryName = $newPath
            $result.UpdatedPaths += "$binaryName -> $newPath"
        }
        
        # Save updated config
        $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force
        
        $result.Success = $true
        
    } catch {
        $result.ErrorMessage = $_.Exception.Message
        
        # Attempt to restore from backup if update failed
        if ($result.BackupPath -and (Test-Path $result.BackupPath)) {
            try {
                Copy-Item -Path $result.BackupPath -Destination $ConfigPath -Force
            } catch {
                # Backup restoration failed
            }
        }
    }
    
    return $result
}

function Write-ValidationLog {
    <#
    .SYNOPSIS
        Validation reporting and logging system with timestamped entries
    .DESCRIPTION
        Logs validation results with comprehensive categorization and audit trails
        Implements 2026 best practices for logging and reporting
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Results,
        
        [Parameter(Mandatory=$false)]
        [string]$LogPath = "Logs\binary_validation.log"
    )
    
    try {
        # Ensure log directory exists
        $logDir = Split-Path $LogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        # Create log entry
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = @"
========================================
Binary Validation Report - $timestamp
========================================
Config Valid: $($Results.ConfigValid)
Total Binaries: $($Results.TotalBinaries)
Valid Binaries: $($Results.ValidBinaries)
Corrected Paths: $($Results.CorrectedPaths)
Errors: $($Results.Errors.Count)
Warnings: $($Results.Warnings.Count)

Binary Test Results:
"@
        
        # Add binary test results
        foreach ($binaryTest in $Results.BinaryTests.GetEnumerator()) {
            $logEntry += [Environment]::NewLine + "  $($binaryTest.Key): $($binaryTest.Value.Valid)"
            if ($binaryTest.Value.ErrorMessage) {
                $logEntry += " - ERROR: $($binaryTest.Value.ErrorMessage)"
            }
        }
        
        if ($Results.PathCorrections.Count -gt 0) {
            $logEntry += [Environment]::NewLine + [Environment]::NewLine + "Path Corrections:"
            foreach ($correction in $Results.PathCorrections.GetEnumerator()) {
                $logEntry += [Environment]::NewLine + "  $($correction.Key): $($correction.Value.OriginalPath) -> $($correction.Value.CorrectedPath) [Strategy: $($correction.Value.SearchStrategy)]"
            }
        }
        
        if ($Results.Errors.Count -gt 0) {
            $logEntry += [Environment]::NewLine + [Environment]::NewLine + "Errors:"
            foreach ($errorMsg in $Results.Errors) {
                $logEntry += [Environment]::NewLine + "  • $errorMsg"
            }
        }
        
        if ($Results.Warnings.Count -gt 0) {
            $logEntry += [Environment]::NewLine + [Environment]::NewLine + "Warnings:"
            foreach ($warning in $Results.Warnings) {
                $logEntry += [Environment]::NewLine + "  • $warning"
            }
        }
        
        $logEntry += [Environment]::NewLine + [Environment]::NewLine + "========================================" + [Environment]::NewLine
        
        # Write to log file
        Add-Content -Path $LogPath -Value $logEntry -Encoding UTF8
        
    } catch {
        Write-Host "⚠️ Failed to write validation log: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

#endregion

#region Utility Functions

function Show-ValidationSummary {
    <#
    .SYNOPSIS
        Display formatted validation summary with color coding
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Results
    )
    
    Write-Host ""
    Write-Host "=== Binary Path Validation Summary ===" -ForegroundColor Magenta
    
    # Overall status
    $overallStatus = if ($Results.ConfigValid -and $Results.Errors.Count -eq 0) { "✅ SUCCESS" } else { "❌ ISSUES FOUND" }
    Write-Host "Overall Status: $overallStatus" -ForegroundColor $(if($Results.ConfigValid -and $Results.Errors.Count -eq 0) {"Green"} else {"Red"})
    
    # Statistics
    Write-Host "Total Binaries Tested: $($Results.TotalBinaries)" -ForegroundColor White
    Write-Host "Valid Binaries: $($Results.ValidBinaries)" -ForegroundColor Green
    Write-Host "Paths Corrected: $($Results.CorrectedPaths)" -ForegroundColor Yellow
    Write-Host "Errors: $($Results.Errors.Count)" -ForegroundColor $(if($Results.Errors.Count -eq 0) {"Green"} else {"Red"})
    Write-Host "Warnings: $($Results.Warnings.Count)" -ForegroundColor Yellow
    
    # Detailed results
    if ($Results.BinaryTests.Count -gt 0) {
        Write-Host ""
        Write-Host "Binary Test Results:" -ForegroundColor Cyan
        
        foreach ($binaryTest in $Results.BinaryTests.GetEnumerator()) {
            $status = if ($binaryTest.Value.Valid) { "✅ VALID" } else { "❌ INVALID" }
            $color = if ($binaryTest.Value.Valid) { "Green" } else { "Red" }
            
            Write-Host "  $($binaryTest.Key): $status" -ForegroundColor $color
            
            if ($binaryTest.Value.ErrorMessage) {
                Write-Host "    Error: $($binaryTest.Value.ErrorMessage)" -ForegroundColor Gray
            }
            
            if ($binaryTest.Value.ResponseTime -gt 0) {
                Write-Host "    Response Time: $($binaryTest.Value.ResponseTime)ms" -ForegroundColor Gray
            }
            
            if ($binaryTest.Value.Version) {
                Write-Host "    Version: $($binaryTest.Value.Version)" -ForegroundColor Gray
            }
        }
    }
    
    # Corrections
    if ($Results.PathCorrections.Count -gt 0) {
        Write-Host ""
        Write-Host "Path Corrections Applied:" -ForegroundColor Cyan
        
        foreach ($correction in $Results.PathCorrections.GetEnumerator()) {
            Write-Host "  $($correction.Key):" -ForegroundColor Yellow
            Write-Host "    From: $($correction.Value.OriginalPath)" -ForegroundColor Gray
            Write-Host "    To: $($correction.Value.CorrectedPath)" -ForegroundColor Green
            Write-Host "    Strategy: $($correction.Value.SearchStrategy)" -ForegroundColor Cyan
            Write-Host "    Search Time: $($correction.Value.SearchTime)ms" -ForegroundColor Gray
        }
    }
    
    # Errors and warnings
    if ($Results.Errors.Count -gt 0) {
        Write-Host ""
        Write-Host "Errors:" -ForegroundColor Red
        foreach ($errorMsg in $Results.Errors) {
            Write-Host "  • $errorMsg" -ForegroundColor Gray
        }
    }
    
    if ($Results.Warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Warnings:" -ForegroundColor Yellow
        foreach ($warning in $Results.Warnings) {
            Write-Host "  • $warning" -ForegroundColor Gray
        }
    }
}

#endregion

# Script is ready to use
Write-Host ""
Write-Host "=== Binary Path Validation Framework Ready ===" -ForegroundColor Green
Write-Host "Use Test-BinaryPathsComprehensive to start validation" -ForegroundColor Cyan
Write-Host ""
