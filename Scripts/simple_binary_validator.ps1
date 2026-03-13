# Simple Binary Path Validator
# Working version for testing binary paths in config.json

function Test-BinaryPaths {
    param(
        [string]$ConfigPath = ".\config.json",
        [switch]$UpdateConfig
    )
    
    Write-Host "=== Binary Path Validation ===" -ForegroundColor Cyan
    
    # Check if config exists
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "❌ Config file not found: $ConfigPath" -ForegroundColor Red
        return
    }
    
    # Load and validate config
    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        Write-Host "✅ Config loaded successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to load config: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    # Test binary paths
    $binaryPaths = $config.binary_paths
    $corrections = @{}
    $validCount = 0
    $totalCount = 0
    
    Write-Host "`nTesting binary paths:" -ForegroundColor Yellow
    
    foreach ($binaryName in $binaryPaths.PSObject.Properties.Name) {
        $binaryPath = $binaryPaths.$binaryName
        $totalCount++
        
        Write-Host "Testing $binaryName`: $binaryPath" -ForegroundColor Gray
        
        if (Test-Path $binaryPath -PathType Leaf) {
            # Test if executable
            try {
                $process = Start-Process -FilePath $binaryPath -ArgumentList "--help" -PassThru -NoNewWindow -RedirectStandardOutput "NUL" -RedirectStandardError "NUL" -ErrorAction Stop
                $process.WaitForExit(5000) | Out-Null
                
                if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 1) {
                    Write-Host "✅ $binaryName - Valid and executable" -ForegroundColor Green
                    $validCount++
                } else {
                    Write-Host "⚠️ $binaryName - File exists but may not be executable" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "❌ $binaryName - File exists but execution failed" -ForegroundColor Red
                
                # Try to find corrected path
                $correctedPath = Find-BinaryCorrection -BinaryName $binaryName
                if ($correctedPath) {
                    Write-Host "🔧 Found correction: $correctedPath" -ForegroundColor Cyan
                    $corrections[$binaryName] = $correctedPath
                }
            }
        } else {
            Write-Host "❌ $binaryName - File not found" -ForegroundColor Red
            
            # Try to find corrected path
            $correctedPath = Find-BinaryCorrection -BinaryName $binaryName
            if ($correctedPath) {
                Write-Host "🔧 Found correction: $correctedPath" -ForegroundColor Cyan
                $corrections[$binaryName] = $correctedPath
            }
        }
    }
    
    # Update config if corrections found
    if ($UpdateConfig -and $corrections.Count -gt 0) {
        Write-Host "`nUpdating config with corrected paths..." -ForegroundColor Yellow
        
        # Create backup
        $backupPath = "$ConfigPath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $ConfigPath $backupPath
        Write-Host "📋 Backup created: $backupPath" -ForegroundColor Gray
        
        # Update paths
        foreach ($correction in $corrections.GetEnumerator()) {
            $config.binary_paths.($correction.Key) = $correction.Value
        }
        
        # Save updated config
        $config | ConvertTo-Json -Depth 10 | Out-File $ConfigPath -Encoding UTF8
        Write-Host "✅ Config updated successfully" -ForegroundColor Green
    }
    
    # Summary
    Write-Host "`n=== Validation Summary ===" -ForegroundColor Magenta
    Write-Host "Total binaries: $totalCount" -ForegroundColor White
    Write-Host "Valid binaries: $validCount" -ForegroundColor Green
    Write-Host "Corrections found: $($corrections.Count)" -ForegroundColor Yellow
    
    if ($corrections.Count -gt 0) {
        Write-Host "`nCorrections:" -ForegroundColor Cyan
        foreach ($correction in $corrections.GetEnumerator()) {
            Write-Host "  $($correction.Key): $($correction.Value)" -ForegroundColor Gray
        }
    }
}

function Find-BinaryCorrection {
    param([string]$BinaryName)
    
    # Binary name mappings
    $binaryMappings = @{
        "main" = @("main.exe", "llama-cli.exe", "llama.exe")
        "server" = @("llama-server.exe", "server.exe")
        "quantize" = @("llama-quantize.exe", "quantize.exe")
        "avx2" = @("main.exe", "llama-cli.exe")
    }
    
    # Search locations
    $searchLocations = @(
        ".\Tools\bin",
        ".\Tools\bin-avx2", 
        ".\bin",
        ".\bin-avx2"
    )
    
    # Try mappings
    if ($binaryMappings.ContainsKey($BinaryName)) {
        foreach ($binaryVariant in $binaryMappings[$BinaryName]) {
            foreach ($location in $searchLocations) {
                $testPath = Join-Path $location $binaryVariant
                if (Test-Path $testPath -PathType Leaf) {
                    return $testPath
                }
            }
        }
    }
    
    # Search Tools/bin for any executable with similar name
    $toolsBinPath = ".\Tools\bin"
    if (Test-Path $toolsBinPath) {
        $allBinaries = Get-ChildItem -Path $toolsBinPath -Filter "*.exe" -File
        
        foreach ($binary in $allBinaries) {
            if ($binary.Name -like "*$BinaryName*" -or $binary.Name -like "*main*" -or $binary.Name -like "*llama*") {
                return $binary.FullName
            }
        }
    }
    
    return $null
}

Write-Host "Binary Path Validator Ready!" -ForegroundColor Green
Write-Host "Use Test-BinaryPaths to validate config.json" -ForegroundColor Cyan
