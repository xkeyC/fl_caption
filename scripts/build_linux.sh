#!/bin/bash

# Linux Build Script for fl_caption
# Similar to build_windows.ps1 but for Linux

# 如果没有通过参数传递，则尝试从环境变量读取
if [[ -z "$1" ]]; then
    ENABLE_NVIDIA="${ENABLE_NVIDIA:-true}"  # 从环境变量读取，默认启用
    echo -e "\033[33mNo NVIDIA setting provided as parameter, using environment variable or default: $ENABLE_NVIDIA\033[0m"
else
    ENABLE_NVIDIA="$1"  # 使用命令行参数
    echo -e "\033[36mUsing NVIDIA setting from parameter: $ENABLE_NVIDIA\033[0m"
fi

echo -e "\033[32mStarting Linux build process...\033[0m"
echo -e "\033[36mNVIDIA Support: $ENABLE_NVIDIA\033[0m"

# Get project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Display debug information
echo -e "\033[35m========== Build Configuration ==========\033[0m"
echo -e "\033[37mParameter 1: ${1:-'Not provided'}\033[0m"
echo -e "\033[37mEnvironment ENABLE_NVIDIA: ${ENABLE_NVIDIA:-'Not set'}\033[0m"
echo -e "\033[37mFinal ENABLE_NVIDIA value: $ENABLE_NVIDIA\033[0m"
echo -e "\033[37mProject Root: $PROJECT_ROOT\033[0m"
echo -e "\033[35m==========================================\033[0m"

update_cargo_toml() {
    local cargo_toml_path="$1"
    local enable_nvidia_feature="$2"
    
    echo -e "\033[33mUpdating Cargo.toml at: $cargo_toml_path\033[0m"
    
    if [[ ! -f "$cargo_toml_path" ]]; then
        echo -e "\033[31mError: Cargo.toml not found at: $cargo_toml_path\033[0m"
        exit 1
    fi
    
    # Create a temporary file for the new content
    local temp_file=$(mktemp)
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^default[[:space:]]*=.*#[[:space:]]*enable[[:space:]]*nvidia[[:space:]]*default ]]; then
            if [[ "$enable_nvidia_feature" == "true" ]]; then
                echo 'default = ["nvidia"] # enable nvidia default' >> "$temp_file"
                echo -e "\033[32mEnabled NVIDIA features\033[0m"
            else
                echo 'default = [] # enable nvidia default' >> "$temp_file"
                echo -e "\033[33mDisabled NVIDIA features\033[0m"
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$cargo_toml_path"
    
    # Replace the original file with the updated content
    mv "$temp_file" "$cargo_toml_path"
    echo -e "\033[32mCargo.toml updated successfully\033[0m"
}

build_flutter() {
    echo -e "\033[36mBuilding Flutter application...\033[0m"
    
    local repo_root="$PROJECT_ROOT"
    local manifest_path="$repo_root/rust/Cargo.toml"
    local target_dir="$repo_root/build/linux/x64/plugins/rust_lib_fl_caption/cargokit_build"
    
    # Build Rust library
    echo -e "\033[33mBuilding Rust library...\033[0m"
    cargo build --manifest-path "$manifest_path" -p "rust_lib_fl_caption" --release --target "x86_64-unknown-linux-gnu" --target-dir "$target_dir"
    
    if [[ $? -ne 0 ]]; then
        echo -e "\033[31mError: Rust build failed\033[0m"
        exit 1
    fi
    
    # Build Flutter application
    echo -e "\033[33mBuilding Flutter application...\033[0m"
    flutter build linux -v
    
    if [[ $? -ne 0 ]]; then
        echo -e "\033[31mError: Flutter build failed\033[0m"
        exit 1
    fi
    
    echo -e "\033[32mFlutter build completed successfully\033[0m"
}

prepare_release_packages() {
    local nvidia_enabled="$1"
    
    echo -e "\033[36mPreparing release packages...\033[0m"
    
    # Copy .so files from cargokit_build to Release folder
    local source_so_path="$PROJECT_ROOT/build/linux/x64/plugins/rust_lib_fl_caption/cargokit_build/x86_64-unknown-linux-gnu/release/examples"
    local release_dir="$PROJECT_ROOT/build/linux/x64/release/bundle"
    
    if [[ -d "$source_so_path" ]]; then
        echo -e "\033[33mCopying .so files from $source_so_path to $release_dir\033[0m"
        find "$source_so_path" -name "*.so" -exec cp {} "$release_dir/" \;
        find "$source_so_path" -name "*.so" -exec basename {} \; | while read filename; do
            echo -e "\033[37mCopied: $filename\033[0m"
        done
    else
        echo -e "\033[31mWarning: Source .so path not found: $source_so_path\033[0m"
    fi
    
    # Copy ortextensions.so
    local ortextensions_so_path="$PROJECT_ROOT/packages/libortextensions/linux_x64/libortextensions.so"
    if [[ -f "$ortextensions_so_path" ]]; then
        cp "$ortextensions_so_path" "$release_dir/"
        echo -e "\033[37mCopied libortextensions.so to $release_dir\033[0m"
    else
        echo -e "\033[31mWarning: libortextensions.so not found at $ortextensions_so_path\033[0m"
    fi
    
    # Decide target directory based on NVIDIA status
    if [[ "$nvidia_enabled" == "true" ]]; then
        # Create release directory structure with CUDA
        local target_dir="$PROJECT_ROOT/build/linux/x64/release/bundle_with_cuda/fl_caption"
        mkdir -p "$target_dir"
        
        # Copy bundle to bundle_with_cuda/fl_caption
        echo -e "\033[33mCopying bundle to $target_dir (WITH CUDA)\033[0m"
        cp -r "$release_dir"/* "$target_dir/"
        
        echo -e "\033[32mRelease package prepared successfully (WITH CUDA)\033[0m"
        echo -e "\033[36m- Target directory: $target_dir\033[0m"
    else
        # Create release directory structure without CUDA
        local target_dir="$PROJECT_ROOT/build/linux/x64/release/bundle_without_cuda/fl_caption"
        mkdir -p "$target_dir"
        
        # Copy bundle to bundle_without_cuda/fl_caption
        echo -e "\033[33mCopying bundle to $target_dir (WITHOUT CUDA)\033[0m"
        cp -r "$release_dir"/* "$target_dir/"
        
        # Remove CUDA .so files from the no-CUDA version
        local cuda_sos=("libonnxruntime_providers_cuda.so" "libonnxruntime_providers_tensorrt.so")
        for so_file in "${cuda_sos[@]}"; do
            local so_path="$target_dir/$so_file"
            if [[ -f "$so_path" ]]; then
                rm -f "$so_path"
                echo -e "\033[33mRemoved CUDA .so: $so_file\033[0m"
            fi
        done
        
        echo -e "\033[32mRelease package prepared successfully (WITHOUT CUDA)\033[0m"
        echo -e "\033[36m- Target directory: $target_dir\033[0m"
    fi
}

# Main execution flow
main() {
    # Update Cargo.toml
    local cargo_toml_path="$PROJECT_ROOT/rust/Cargo.toml"
    update_cargo_toml "$cargo_toml_path" "$ENABLE_NVIDIA"
    
    # Build Flutter application
    build_flutter
    
    # Prepare release packages
    prepare_release_packages "$ENABLE_NVIDIA"
    
    echo -e "\033[32mBuild process completed successfully!\033[0m"
}

# Execute main function with error handling
if ! main; then
    echo -e "\033[31mBuild process failed!\033[0m"
    exit 1
fi
