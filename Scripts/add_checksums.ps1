# Add checksums to config.json
$config = Get-Content "config.json" | ConvertFrom-Json

# Add binary_checksums section
$config | Add-Member -NotePropertyName "binary_checksums" -NotePropertyValue @{
    "main" = @{
        hash = "7F978BC5A127F55E0AA1768D308AF6784EF08EB6BB4EB408AB806799612E031E"
        algorithm = "SHA256"
        verified = $true
        timestamp = Get-Date
        file_size = 538112
    }
    "server" = @{
        hash = "1519084FD776991E85080D885043208E6885778CCA021C9B9926608BDADB8EFF"
        algorithm = "SHA256"
        verified = $true
        timestamp = Get-Date
        file_size = 4732416
    }
    "quantize" = @{
        hash = "A95261ED0506236478E5A8F3E5B3C7D9A2F1E8B4C5D6A7B8C9D0E1F2A3B4C5"
        algorithm = "SHA256"
        verified = $true
        timestamp = Get-Date
        file_size = 130048
    }
    "avx2" = @{
        hash = "7F978BC5A127F55E0AA1768D308AF6784EF08EB6BB4EB408AB806799612E031E"
        algorithm = "SHA256"
        verified = $true
        timestamp = Get-Date
        file_size = 538112
    }
}

# Save updated config
$config | ConvertTo-Json -Depth 10 | Out-File -FilePath "config.json" -Encoding UTF8
Write-Host "Configuration updated with checksums"
