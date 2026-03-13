# Binary Integrity Verification - Simple Version
Write-Host "Starting binary integrity verification..."

# Load config
$config = Get-Content "config.json" | ConvertFrom-Json
$binaryPaths = $config.binary_paths

Write-Host "Found $($binaryPaths.PSObject.Properties.Name.Count) binaries"

# Check each binary
foreach ($binaryName in $binaryPaths.PSObject.Properties.Name) {
    $binaryPath = $binaryPaths.$binaryName
    Write-Host "Checking: $binaryName -> $binaryPath"
    
    if (Test-Path $binaryPath) {
        $hash = Get-FileHash -Path $binaryPath -Algorithm SHA256
        Write-Host "  Hash: $($hash.Hash.Substring(0,16))..."
        Write-Host "  Size: $([math]::Round((Get-Item $binaryPath).Length / 1MB, 2)) MB"
    } else {
        Write-Host "  MISSING: File not found"
    }
    Write-Host ""
}

Write-Host "Verification completed."
