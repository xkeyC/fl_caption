param(
    [string]$EnableNvidia = "false"  # 默认禁用 NVIDIA 功能
)

Write-Host "Building WITHOUT NVIDIA support..." -ForegroundColor Yellow

# 调用主构建脚本
& "$PSScriptRoot\build_windows.ps1" -EnableNvidia $EnableNvidia
