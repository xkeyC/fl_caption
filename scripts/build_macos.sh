#!/bin/bash

# macOS Build Script for fl_caption
# Based on build_linux.sh but adapted for macOS

# Check if this is a pre-operation call (just disable NVIDIA)
if [[ "$1" == "--disable-nvidia-only" ]]; then
    echo -e "\033[36mRunning NVIDIA disable pre-operation for macOS...\033[0m"
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Disable NVIDIA function
    disable_nvidia() {
        local cargo_toml_path="$PROJECT_ROOT/rust/Cargo.toml"
        echo -e "\033[33mDisabling NVIDIA features in Cargo.toml for macOS pre-operation...\033[0m"
        
        if [[ ! -f "$cargo_toml_path" ]]; then
            echo -e "\033[31mError: Cargo.toml not found at: $cargo_toml_path\033[0m"
            exit 1
        fi
        
        # Create a temporary file for the new content
        local temp_file=$(mktemp)
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^default[[:space:]]*=.*#[[:space:]]*enable[[:space:]]*nvidia[[:space:]]*default ]]; then
                echo 'default = [] # enable nvidia default' >> "$temp_file"
                echo -e "\033[32mDisabled NVIDIA features for macOS (uses Metal acceleration)\033[0m"
            else
                echo "$line" >> "$temp_file"
            fi
        done < "$cargo_toml_path"
        
        # Replace the original file with the updated content
        mv "$temp_file" "$cargo_toml_path"
        echo -e "\033[32mNVIDIA pre-operation completed successfully\033[0m"
    }
    
    # Execute the disable function and exit
    disable_nvidia
    exit 0
fi

# macOS always disables NVIDIA (uses Metal instead of CUDA)
ENABLE_NVIDIA="false"
echo -e "\033[36mmacOS build always disables NVIDIA (uses Metal acceleration instead)\033[0m"

echo -e "\033[32mStarting macOS build process...\033[0m"
echo -e "\033[36mNVIDIA Support: $ENABLE_NVIDIA (forced disabled for macOS)\033[0m"

# Get project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Display debug information
echo -e "\033[35m========== Build Configuration ==========\033[0m"
echo -e "\033[37mPlatform: macOS\033[0m"
echo -e "\033[37mNVIDIA Support: $ENABLE_NVIDIA (forced disabled)\033[0m"
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
                echo -e "\033[33mDisabled NVIDIA features (macOS uses Metal)\033[0m"
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
    
    # Detect the target architecture (Apple Silicon vs Intel)
    local arch=$(uname -m)
    local target_arch
    if [[ "$arch" == "arm64" ]]; then
        target_arch="aarch64-apple-darwin"
    else
        target_arch="x86_64-apple-darwin"
    fi
    
    echo -e "\033[33mDetected architecture: $arch, using target: $target_arch\033[0m"
    
    local target_dir="$repo_root/build/macos/Build/Products/plugins/rust_lib_fl_caption/cargokit_build"
    
    # 确保 cargokit_build 目录存在
    if [[ ! -d "$target_dir" ]]; then
        echo -e "\033[33mCreating cargokit_build directory: $target_dir\033[0m"
        mkdir -p "$target_dir"
    fi
    
    # 确保 native assets 目录存在
    local native_assets_dir="$repo_root/build/native_assets/macos"
    if [[ ! -d "$native_assets_dir" ]]; then
        echo -e "\033[33mCreating native assets directory: $native_assets_dir\033[0m"
        mkdir -p "$native_assets_dir"
    fi
    
    # Build Rust library
    echo -e "\033[33mBuilding Rust library...\033[0m"
    cargo build --manifest-path "$manifest_path" -p "rust_lib_fl_caption" --release --target "$target_arch" --target-dir "$target_dir"
    
    if [[ $? -ne 0 ]]; then
        echo -e "\033[31mError: Rust build failed\033[0m"
        exit 1
    fi
    
    # Build Flutter application
    echo -e "\033[33mBuilding Flutter application...\033[0m"
    flutter build macos -v
    
    if [[ $? -ne 0 ]]; then
        echo -e "\033[31mError: Flutter build failed\033[0m"
        exit 1
    fi
    
    echo -e "\033[32mFlutter build completed successfully\033[0m"
}

prepare_release_packages() {
    echo -e "\033[36mPreparing release packages...\033[0m"
    
    # Detect the target architecture for finding the right ortextensions library
    local arch=$(uname -m)
    local ortextensions_dir
    if [[ "$arch" == "arm64" ]]; then
        ortextensions_dir="macos_aarch64"
    else
        # For Intel Macs, we might need to create a separate directory
        # For now, use the same aarch64 directory as it should work on both
        ortextensions_dir="macos_aarch64"
    fi
    
    local release_dir="$PROJECT_ROOT/build/macos/Build/Products/Release"
    
    # Ensure the release directory exists
    if [[ ! -d "$release_dir" ]]; then
        echo -e "\033[31mError: Release directory not found: $release_dir\033[0m"
        exit 1
    fi
    
    # Copy libortextensions.dylib
    local ortextensions_dylib_path="$PROJECT_ROOT/packages/libortextensions/$ortextensions_dir/libortextensions.dylib"
    if [[ -f "$ortextensions_dylib_path" ]]; then
        # Copy to the app bundle
        local app_bundle="$release_dir/fl_caption.app"
        local frameworks_dir="$app_bundle/Contents/Frameworks"
        
        # Create Frameworks directory if it doesn't exist
        if [[ ! -d "$frameworks_dir" ]]; then
            mkdir -p "$frameworks_dir"
            echo -e "\033[33mCreated Frameworks directory: $frameworks_dir\033[0m"
        fi
        
        cp "$ortextensions_dylib_path" "$frameworks_dir/"
        echo -e "\033[37mCopied libortextensions.dylib to $frameworks_dir\033[0m"
    else
        echo -e "\033[31mWarning: libortextensions.dylib not found at $ortextensions_dylib_path\033[0m"
    fi
    
    echo -e "\033[32mRelease package prepared successfully (WITHOUT CUDA - macOS uses Metal)\033[0m"
    echo -e "\033[36m- Release directory: $release_dir\033[0m"
    echo -e "\033[36m- App bundle: $release_dir/fl_caption.app\033[0m"
}

# Main execution flow
main() {
    # Update Cargo.toml (always disable NVIDIA for macOS)
    local cargo_toml_path="$PROJECT_ROOT/rust/Cargo.toml"
    update_cargo_toml "$cargo_toml_path" "$ENABLE_NVIDIA"
    
    # Build Flutter application
    build_flutter
    
    # Prepare release packages
    prepare_release_packages
    
    echo -e "\033[32mBuild process completed successfully!\033[0m"
}

# Execute main function with error handling
if ! main; then
    echo -e "\033[31mBuild process failed!\033[0m"
    exit 1
fi