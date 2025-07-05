param(
    [string]$EnableNvidia = $null  # 控制是否启用 NVIDIA 功能
)

# 如果没有通过参数传递，则尝试从环境变量读取
if ([string]::IsNullOrEmpty($EnableNvidia)) {
    $EnableNvidia = $env:ENABLE_NVIDIA
    if ([string]::IsNullOrEmpty($EnableNvidia)) {
        $EnableNvidia = "true"  # 默认启用
        Write-Host "No NVIDIA setting provided, defaulting to enabled" -ForegroundColor Yellow
    } else {
        Write-Host "Using NVIDIA setting from environment variable: $EnableNvidia" -ForegroundColor Cyan
    }
} else {
    Write-Host "Using NVIDIA setting from parameter: $EnableNvidia" -ForegroundColor Cyan
}

Write-Host "Starting Windows build process..." -ForegroundColor Green
Write-Host "NVIDIA Support: $EnableNvidia" -ForegroundColor Cyan

# 获取项目根目录
$projectRoot = Split-Path -Parent $PSScriptRoot

# 显示调试信息
Write-Host "========== Build Configuration ==========" -ForegroundColor Magenta
Write-Host "Parameter EnableNvidia: $($args[0] ?? 'Not provided')" -ForegroundColor Gray
Write-Host "Environment ENABLE_NVIDIA: $($env:ENABLE_NVIDIA ?? 'Not set')" -ForegroundColor Gray
Write-Host "Final EnableNvidia value: $EnableNvidia" -ForegroundColor Gray
Write-Host "Project Root: $projectRoot" -ForegroundColor Gray
Write-Host "==========================================" -ForegroundColor Magenta

function Update-CargoToml {
    param(
        [string]$CargoTomlPath,
        [bool]$EnableNvidiaFeature
    )
    
    Write-Host "Updating Cargo.toml at: $CargoTomlPath" -ForegroundColor Yellow
    
    if (-not (Test-Path $CargoTomlPath)) {
        Write-Error "Cargo.toml not found at: $CargoTomlPath"
        exit 1
    }
    
    $content = Get-Content $CargoTomlPath
    $newContent = @()
    
    foreach ($line in $content) {
        if ($line -match "^default\s*=.*# enable nvidia default") {
            if ($EnableNvidiaFeature) {
                $newContent += 'default = ["nvidia"] # enable nvidia default'
                Write-Host "Enabled NVIDIA features" -ForegroundColor Green
            } else {
                $newContent += 'default = [] # enable nvidia default'
                Write-Host "Disabled NVIDIA features" -ForegroundColor Yellow
            }
        } else {
            $newContent += $line
        }
    }
    
    Set-Content -Path $CargoTomlPath -Value $newContent -Encoding UTF8
    Write-Host "Cargo.toml updated successfully" -ForegroundColor Green
}

function Build-Flutter {
    Write-Host "Building Flutter application..." -ForegroundColor Cyan
    
    $repoRoot = $projectRoot -replace '\\', '/'
    $manifestPath = "$repoRoot/rust/Cargo.toml"
    $targetDir = "$repoRoot/build/windows/x64/plugins/rust_lib_fl_caption/cargokit_build"

    # 确保 cargokit_build 目录存在
    $targetDirWindows = $targetDir -replace '/', '\'
    if (-not (Test-Path $targetDirWindows)) {
        Write-Host "Creating cargokit_build directory: $targetDirWindows" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $targetDirWindows -Force | Out-Null
    }

    # 确保 native assets 目录存在
    $nativeAssetsDir = "$projectRoot/build/native_assets/windows"
    if (-not (Test-Path $nativeAssetsDir)) {
        Write-Host "Creating native assets directory: $nativeAssetsDir" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $nativeAssetsDir -Force | Out-Null
    }
    
    # 构建 Rust 库
    Write-Host "Building Rust library..." -ForegroundColor Yellow
    $cargoCmd = "rustup run stable cargo build --manifest-path `"$manifestPath`" -p `"rust_lib_fl_caption`" --release --target `"x86_64-pc-windows-msvc`" --target-dir `"$targetDir`""
    Invoke-Expression $cargoCmd
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Rust build failed"
        exit 1
    }
    
    # 构建 Flutter 应用
    Write-Host "Building Flutter application..." -ForegroundColor Yellow
    flutter build windows -v
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter build failed"
        exit 1
    }
    
    Write-Host "Flutter build completed successfully" -ForegroundColor Green
}

function Prepare-ReleasePackages {
    param(
        [bool]$NvidiaEnabled
    )
    
    Write-Host "Preparing release packages..." -ForegroundColor Cyan
    
    # 复制 DLL 文件从 cargokit_build 到 Release 文件夹
    $sourceDllPath = "$projectRoot\build\windows\x64\plugins\rust_lib_fl_caption\cargokit_build\x86_64-pc-windows-msvc\release\examples"
    $releaseDir = "$projectRoot\build\windows\x64\runner\Release"
    
    if (Test-Path $sourceDllPath) {
        Write-Host "Copying DLL files from $sourceDllPath to $releaseDir" -ForegroundColor Yellow
        Get-ChildItem -Path $sourceDllPath -Filter "*.dll" | ForEach-Object {
            Copy-Item $_.FullName -Destination $releaseDir -Force
            Write-Host "Copied: $($_.Name)" -ForegroundColor Gray
        }
    } else {
        Write-Host "Warning: Source DLL path not found: $sourceDllPath" -ForegroundColor Red
    }
    
    # 复制 ortextensions.dll
    $ortextensionsDllPath = "$projectRoot\packages\libortextensions\windows_x64\ortextensions.dll"
    if (Test-Path $ortextensionsDllPath) {
        Copy-Item $ortextensionsDllPath -Destination $releaseDir -Force
        Write-Host "Copied ortextensions.dll to $releaseDir" -ForegroundColor Gray
    } else {
        Write-Host "Warning: ortextensions.dll not found at $ortextensionsDllPath" -ForegroundColor Red
    }
    
    # 根据 NVIDIA 启用状态决定复制到哪个目录
    if ($NvidiaEnabled) {
        # 创建带 CUDA 的发布目录结构
        $targetDir = "$projectRoot\build\windows\x64\runner\Release_with_cuda\fl_caption"
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        
        # 复制 Release 到 Release_with_cuda/fl_caption
        Write-Host "Copying Release to $targetDir (WITH CUDA)" -ForegroundColor Yellow
        Copy-Item -Path "$releaseDir\*" -Destination $targetDir -Recurse -Force
        
        Write-Host "Release package prepared successfully (WITH CUDA)" -ForegroundColor Green
        Write-Host "- Target directory: $targetDir" -ForegroundColor Cyan
    } else {
        # 创建不带 CUDA 的发布目录结构
        $targetDir = "$projectRoot\build\windows\x64\runner\Release_without_cuda\fl_caption"
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        
        # 复制 Release 到 Release_without_cuda/fl_caption
        Write-Host "Copying Release to $targetDir (WITHOUT CUDA)" -ForegroundColor Yellow
        Copy-Item -Path "$releaseDir\*" -Destination $targetDir -Recurse -Force
        
        # 从不带 CUDA 版本中移除 CUDA DLL
        $cudaDlls = @("onnxruntime_providers_cuda.dll", "onnxruntime_providers_tensorrt.dll")
        foreach ($dll in $cudaDlls) {
            $dllPath = Join-Path $targetDir $dll
            if (Test-Path $dllPath) {
                Remove-Item $dllPath -Force
                Write-Host "Removed CUDA DLL: $dll" -ForegroundColor Yellow
            }
        }
        
        Write-Host "Release package prepared successfully (WITHOUT CUDA)" -ForegroundColor Green
        Write-Host "- Target directory: $targetDir" -ForegroundColor Cyan
    }
}

# 主执行流程
try {
    # 更新 Cargo.toml
    $cargoTomlPath = "$projectRoot\rust\Cargo.toml"
    $enableNvidiaFeature = $EnableNvidia -eq "true"
    Update-CargoToml -CargoTomlPath $cargoTomlPath -EnableNvidiaFeature $enableNvidiaFeature
    
    # 构建 Flutter 应用
    Build-Flutter
    
    # 准备发布包
    Prepare-ReleasePackages -NvidiaEnabled $enableNvidiaFeature
    
    Write-Host "Build process completed successfully!" -ForegroundColor Green
} catch {
    Write-Error "Build process failed: $($_.Exception.Message)"
    exit 1
}
test_env_vars