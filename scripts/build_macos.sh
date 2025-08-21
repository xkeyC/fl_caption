#!/bin/bash

# macOS Build Script for fl_caption
# Uses shared utilities for better code reuse

# Source shared build utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build_utils.sh"

# Check if this is a pre-operation call (temporarily disable NVIDIA for build_runner)
if [[ "$1" == "--disable-nvidia-only" ]]; then
    log_info "Running NVIDIA disable pre-operation for macOS..."
    PROJECT_ROOT="$(get_project_root)"
    
    # Temporarily disable NVIDIA for build_runner execution
    cargo_toml_path="$PROJECT_ROOT/rust/Cargo.toml"
    disable_nvidia_temporarily "$cargo_toml_path" ".macos-pre-backup"
    log_success "NVIDIA pre-operation completed successfully"
    log_warning "Remember to restore after build_runner completes!"
    exit 0
fi

# Check if this is a restore operation
if [[ "$1" == "--restore-nvidia" ]]; then
    log_info "Restoring NVIDIA settings from backup..."
    PROJECT_ROOT="$(get_project_root)"
    cargo_toml_path="$PROJECT_ROOT/rust/Cargo.toml"
    restore_nvidia_from_backup "$cargo_toml_path" ".macos-pre-backup"
    exit 0
fi

# macOS always disables NVIDIA (uses Metal instead of CUDA)
ENABLE_NVIDIA="false"
PROJECT_ROOT="$(get_project_root)"

log_success "Starting macOS build process..."
log_info "macOS build always disables NVIDIA (uses Metal acceleration instead)"

display_build_config "macOS" "$ENABLE_NVIDIA" "$PROJECT_ROOT"

build_flutter() {
    log_info "Building Flutter application..."
    
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
    
    log_info "Detected architecture: $arch, using target: $target_arch"
    
    local target_dir="$repo_root/build/macos/Build/Products/plugins/rust_lib_fl_caption/cargokit_build"
    local native_assets_dir="$repo_root/build/native_assets/macos"
    
    # Create necessary directories
    create_build_directories "$target_dir" "$native_assets_dir"
    
    # Build Rust library using shared function
    build_rust_library "$manifest_path" "$target_arch" "$target_dir"
    
    # Build Flutter application using shared function
    build_flutter_app "macos"
}

prepare_release_packages() {
    log_info "Preparing release packages..."
    
    # Detect the target architecture for finding the right ortextensions library
    local arch=$(uname -m)
    local ortextensions_dir
    if [[ "$arch" == "arm64" ]]; then
        ortextensions_dir="macos_aarch64"
    else
        # For Intel Macs, use the same aarch64 directory as it should work on both
        ortextensions_dir="macos_aarch64"
    fi
    
    local release_dir="$PROJECT_ROOT/build/macos/Build/Products/Release"
    
    # Ensure the release directory exists
    if [[ ! -d "$release_dir" ]]; then
        log_error "Error: Release directory not found: $release_dir"
        exit 1
    fi
    
    # Copy libortextensions.dylib using shared utility function
    local ortextensions_dylib_path="$PROJECT_ROOT/packages/libortextensions/$ortextensions_dir/libortextensions.dylib"
    local app_bundle="$release_dir/fl_caption.app"
    local frameworks_dir="$app_bundle/Contents/Frameworks"
    
    # Create Frameworks directory if it doesn't exist
    create_build_directories "$frameworks_dir"
    
    # Copy the library
    copy_file_with_log "$ortextensions_dylib_path" "$frameworks_dir/" "libortextensions.dylib"
    
    log_success "Release package prepared successfully (WITHOUT CUDA - macOS uses Metal)"
    log_info "- Release directory: $release_dir"
    log_info "- App bundle: $app_bundle"
}

# Main execution flow
main() {
    # Update Cargo.toml using shared utility function
    local cargo_toml_path="$PROJECT_ROOT/rust/Cargo.toml"
    update_cargo_toml "$cargo_toml_path" "$ENABLE_NVIDIA"
    
    # Build Flutter application
    build_flutter
    
    # Prepare release packages
    prepare_release_packages
    
    log_success "Build process completed successfully!"
}

# Execute main function with error handling
if ! main; then
    log_error "Build process failed!"
    exit 1
fi