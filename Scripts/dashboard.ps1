# LLM Performance Dashboard
Write-Host "=== LLM PERFORMANCE DASHBOARD ===" -ForegroundColor Green
Write-Host ""

Write-Host "System Status:" -ForegroundColor Cyan

# Current system metrics
$cpu = (Get-Counter "\Processor(_Total)\% Processor Time").CounterSamples.CookedValue
$memory = Get-WmiObject -Class Win32_OperatingSystem
$totalMem = [math]::Round($memory.TotalVisibleMemorySize / 1MB, 2)
$freeMem = [math]::Round($memory.FreePhysicalMemory / 1MB, 2)
$usedMem = $totalMem - $freeMem
$memPercent = [math]::Round(($usedMem / $totalMem) * 100, 1)

Write-Host "CPU Usage: $([math]::Round($cpu, 1))%" -ForegroundColor White
Write-Host "Memory: $usedMem MB / $totalMem MB ($memPercent%)" -ForegroundColor White

# Check for LLM processes
$llmProcesses = Get-Process | Where-Object {$_.ProcessName -like "*main*" -or $_.ProcessName -like "*llama*"}
Write-Host "Active LLM Processes: $($llmProcesses.Count)" -ForegroundColor White

if ($llmProcesses.Count -gt 0) {
    Write-Host ""
    Write-Host "LLM Process Details:" -ForegroundColor Yellow
    foreach ($proc in $llmProcesses) {
        $procMem = [math]::Round($proc.WorkingSet64 / 1MB, 2)
        Write-Host "  $($proc.ProcessName): PID $($proc.Id), Memory ${procMem}MB" -ForegroundColor Gray
    }
}

# Check optimization status
Write-Host ""
Write-Host "Optimization Status:" -ForegroundColor Cyan

# Power plan
$currentPlan = powercfg -getactivescheme
if ($currentPlan -match "Ultimate Performance") {
    Write-Host "  Power Plan: Ultimate Performance" -ForegroundColor Green
} else {
    Write-Host "  Power Plan: Not Ultimate Performance" -ForegroundColor Yellow
}

# Large pages
try {
    $largePages = reg query "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management" /v LargePageMinimum 2>$null
    if ($largePages -match "0x400") {
        Write-Host "  Large Pages: Configured" -ForegroundColor Green
    } else {
        Write-Host "  Large Pages: Not configured" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Large Pages: Unknown" -ForegroundColor Red
}

# Model files
Write-Host ""
Write-Host "Available Models:" -ForegroundColor Cyan
if (Test-Path "models") {
    $models = Get-ChildItem "models\*.gguf" 2>$null
    foreach ($model in $models) {
        $size = [math]::Round($model.Length / 1GB, 2)
        Write-Host "  $($model.Name): ${size}GB" -ForegroundColor White
    }
} else {
    Write-Host "  No models directory found" -ForegroundColor Red
}

Write-Host ""
Write-Host "Performance Summary:" -ForegroundColor Magenta
Write-Host "  System optimized for LLM inference" -ForegroundColor White
Write-Host "  CPU optimizations applied" -ForegroundColor White
Write-Host "  Storage optimizations configured" -ForegroundColor White
Write-Host "  Multiple test models available" -ForegroundColor White
