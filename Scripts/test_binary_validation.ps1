# Simple test for binary validation framework
. ".\binary_path_validator.ps1"

Write-Host "Testing binary validation framework..." -ForegroundColor Cyan

# Test the main function
$results = Test-BinaryPathsComprehensive -UpdateConfig -Detailed

# Show results
Show-ValidationSummary -Results $results

Write-Host "Test completed!" -ForegroundColor Green
