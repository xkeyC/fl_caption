#!/bin/bash

# Shared Build Utilities for fl_caption
# Common functions for Linux, macOS, and other platform builds

# Color codes for consistent output formatting
readonly COLOR_RED='\033[31m'
readonly COLOR_GREEN='\033[32m'
readonly COLOR_YELLOW='\033[33m'
readonly COLOR_BLUE='\033[34m'
readonly COLOR_MAGENTA='\033[35m'
readonly COLOR_CYAN='\033[36m'
readonly COLOR_WHITE='\033[37m'
readonly COLOR_RESET='\033[0m'

# Log functions with consistent formatting
log_info() {
    echo -e "${COLOR_CYAN}$1${COLOR_RESET}"
}

log_success() {
    echo -e "${COLOR_GREEN}$1${COLOR_RESET}"
}

log_warning() {
    echo -e "${COLOR_YELLOW}$1${COLOR_RESET}"
}

log_error() {
    echo -e "${COLOR_RED}$1${COLOR_RESET}"
}

log_debug() {
    echo -e "${COLOR_WHITE}$1${COLOR_RESET}"
}

log_header() {
    echo -e "${COLOR_MAGENTA}$1${COLOR_RESET}"
}

# Get project root directory (common across all scripts)
get_project_root() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}

# Display build configuration in a standardized format
display_build_config() {
    local platform="$1"
    local enable_nvidia="$2"
    local project_root="$3"
    
    log_header "========== Build Configuration =========="
    log_debug "Platform: $platform"
    log_debug "NVIDIA Support: $enable_nvidia"
    log_debug "Project Root: $project_root"
    log_header "=========================================="
}

# Temporarily disable NVIDIA features in Cargo.toml for pre-operations
# This does NOT modify the file permanently - it creates a backup and restores after operation
disable_nvidia_temporarily() {
    local cargo_toml_path="$1"
    local backup_suffix="${2:-.backup}"
    
    log_info "Temporarily disabling NVIDIA features for pre-operation..."
    
    if [[ ! -f "$cargo_toml_path" ]]; then
        log_error "Error: Cargo.toml not found at: $cargo_toml_path"
        return 1
    fi
    
    # Create backup
    cp "$cargo_toml_path" "${cargo_toml_path}${backup_suffix}"
    
    # Create temporary file with NVIDIA disabled
    local temp_file=$(mktemp)
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^default[[:space:]]*=.*#[[:space:]]*enable[[:space:]]*nvidia[[:space:]]*default ]]; then
            echo 'default = [] # enable nvidia default' >> "$temp_file"
            log_success "NVIDIA features temporarily disabled"
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$cargo_toml_path"
    
    # Replace with disabled version
    mv "$temp_file" "$cargo_toml_path"
    log_success "Temporary NVIDIA disable completed"
}

# Restore NVIDIA settings from backup
restore_nvidia_from_backup() {
    local cargo_toml_path="$1"
    local backup_suffix="${2:-.backup}"
    local backup_path="${cargo_toml_path}${backup_suffix}"
    
    if [[ -f "$backup_path" ]]; then
        mv "$backup_path" "$cargo_toml_path"
        log_success "Restored original Cargo.toml from backup"
    else
        log_warning "No backup found at: $backup_path"
    fi
}

# Update Cargo.toml with NVIDIA feature control (permanent change during build)
update_cargo_toml() {
    local cargo_toml_path="$1"
    local enable_nvidia_feature="$2"
    
    log_info "Updating Cargo.toml at: $cargo_toml_path"
    
    if [[ ! -f "$cargo_toml_path" ]]; then
        log_error "Error: Cargo.toml not found at: $cargo_toml_path"
        return 1
    fi
    
    # Create a temporary file for the new content
    local temp_file=$(mktemp)
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^default[[:space:]]*=.*#[[:space:]]*enable[[:space:]]*nvidia[[:space:]]*default ]]; then
            if [[ "$enable_nvidia_feature" == "true" ]]; then
                echo 'default = ["nvidia"] # enable nvidia default' >> "$temp_file"
                log_success "Enabled NVIDIA features"
            else
                echo 'default = [] # enable nvidia default' >> "$temp_file"
                log_warning "Disabled NVIDIA features"
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$cargo_toml_path"
    
    # Replace the original file with the updated content
    mv "$temp_file" "$cargo_toml_path"
    log_success "Cargo.toml updated successfully"
}

# Create necessary build directories
create_build_directories() {
    local directories=("$@")
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_info "Creating directory: $dir"
            mkdir -p "$dir"
        fi
    done
}

# Generic Rust build function
build_rust_library() {
    local manifest_path="$1"
    local target="$2"
    local target_dir="$3"
    local package_name="${4:-rust_lib_fl_caption}"
    
    log_info "Building Rust library..."
    log_debug "Manifest: $manifest_path"
    log_debug "Target: $target"
    log_debug "Target Dir: $target_dir"
    log_debug "Package: $package_name"
    
    cargo build --manifest-path "$manifest_path" -p "$package_name" --release --target "$target" --target-dir "$target_dir"
    
    if [[ $? -ne 0 ]]; then
        log_error "Error: Rust build failed"
        return 1
    fi
    
    log_success "Rust library build completed"
}

# Generic Flutter build function
build_flutter_app() {
    local platform="$1"
    
    log_info "Building Flutter application for $platform..."
    flutter build "$platform" -v
    
    if [[ $? -ne 0 ]]; then
        log_error "Error: Flutter build failed"
        return 1
    fi
    
    log_success "Flutter build completed successfully"
}

# Copy file with logging
copy_file_with_log() {
    local source="$1"
    local dest="$2"
    local description="${3:-file}"
    
    if [[ -f "$source" ]]; then
        cp "$source" "$dest"
        log_debug "Copied $description from $source to $dest"
        return 0
    else
        log_warning "Warning: $description not found at $source"
        return 1
    fi
}

# Check if this script is being sourced (not executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_error "This script should be sourced, not executed directly"
    log_info "Usage: source build_utils.sh"
    exit 1
fi