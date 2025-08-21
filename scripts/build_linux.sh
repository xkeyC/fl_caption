#!/bin/bash

# Linux Build Script for fl_caption
# Uses shared utilities for better code reuse

# Source shared build utilities  
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build_utils.sh"

# Get NVIDIA setting from parameter or environment
if [[ -z "$1" ]]; then
    ENABLE_NVIDIA="${ENABLE_NVIDIA:-true}"  # Default to enabled for Linux
    log_warning "No NVIDIA setting provided as parameter, using environment variable or default: $ENABLE_NVIDIA"
else
    ENABLE_NVIDIA="$1"
    log_info "Using NVIDIA setting from parameter: $ENABLE_NVIDIA"
fi

PROJECT_ROOT="$(get_project_root)"

log_success "Starting Linux build process..."
display_build_config "Linux" "$ENABLE_NVIDIA" "$PROJECT_ROOT"

build_flutter() {
    log_info "Building Flutter application..."
    
    local repo_root="$PROJECT_ROOT"
    local manifest_path="$repo_root/rust/Cargo.toml"
    local target_dir="$repo_root/build/linux/x64/plugins/rust_lib_fl_caption/cargokit_build"
    local native_assets_dir="$repo_root/build/native_assets/linux"
    
    # Create necessary directories
    create_build_directories "$target_dir" "$native_assets_dir"
    
    # Build Rust library using shared function
    build_rust_library "$manifest_path" "x86_64-unknown-linux-gnu" "$target_dir"
    
    # Build Flutter application using shared function
    build_flutter_app "linux"
}

prepare_release_packages() {
    local nvidia_enabled="$1"
    
    log_info "Preparing release packages..."
    
    # Copy .so files from cargokit_build to Release folder
    local source_so_path="$PROJECT_ROOT/build/linux/x64/plugins/rust_lib_fl_caption/cargokit_build/x86_64-unknown-linux-gnu/release/examples"
    local release_dir="$PROJECT_ROOT/build/linux/x64/release/bundle"
    
    if [[ -d "$source_so_path" ]]; then
        log_info "Copying .so files from $source_so_path to $release_dir"
        find "$source_so_path" -name "*.so" -exec cp {} "$release_dir/" \;
        find "$source_so_path" -name "*.so" -exec basename {} \; | while read filename; do
            log_debug "Copied: $filename"
        done
    else
        log_warning "Warning: Source .so path not found: $source_so_path"
    fi
    
    # Copy ortextensions.so using shared utility function
    local ortextensions_so_path="$PROJECT_ROOT/packages/libortextensions/linux_x64/libortextensions.so"
    copy_file_with_log "$ortextensions_so_path" "$release_dir/" "libortextensions.so"
    
    # Decide target directory based on NVIDIA status
    if [[ "$nvidia_enabled" == "true" ]]; then
        # Create release directory structure with CUDA
        local target_dir="$PROJECT_ROOT/build/linux/x64/release/bundle_with_cuda/fl_caption"
        create_build_directories "$target_dir"
        
        # Copy bundle to bundle_with_cuda/fl_caption
        log_info "Copying bundle to $target_dir (WITH CUDA)"
        cp -r "$release_dir"/* "$target_dir/"
        
        log_success "Release package prepared successfully (WITH CUDA)"
        log_info "- Target directory: $target_dir"
    else
        # Create release directory structure without CUDA
        local target_dir="$PROJECT_ROOT/build/linux/x64/release/bundle_without_cuda/fl_caption"
        create_build_directories "$target_dir"
        
        # Copy bundle to bundle_without_cuda/fl_caption
        log_info "Copying bundle to $target_dir (WITHOUT CUDA)"
        cp -r "$release_dir"/* "$target_dir/"
        
        # Remove CUDA .so files from the no-CUDA version
        local cuda_sos=("libonnxruntime_providers_cuda.so" "libonnxruntime_providers_tensorrt.so")
        for so_file in "${cuda_sos[@]}"; do
            local so_path="$target_dir/$so_file"
            if [[ -f "$so_path" ]]; then
                rm -f "$so_path"
                log_warning "Removed CUDA .so: $so_file"
            fi
        done
        
        log_success "Release package prepared successfully (WITHOUT CUDA)"
        log_info "- Target directory: $target_dir"
    fi
}

# Main execution flow
main() {
    # Update Cargo.toml using shared utility function
    local cargo_toml_path="$PROJECT_ROOT/rust/Cargo.toml"
    update_cargo_toml "$cargo_toml_path" "$ENABLE_NVIDIA"
    
    # Build Flutter application
    build_flutter
    
    # Prepare release packages
    prepare_release_packages "$ENABLE_NVIDIA"
    
    log_success "Build process completed successfully!"
}

# Execute main function with error handling
if ! main; then
    log_error "Build process failed!"
    exit 1
fi
