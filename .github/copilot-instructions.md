# FL Caption Development Instructions

**ALWAYS follow these instructions first** and fallback to additional search and context gathering only if the information here is incomplete or found to be in error.

## Project Overview
FL Caption is a Flutter desktop application with Rust backend for real-time subtitle/caption generation using AI models (Whisper). It supports Windows, Linux, and macOS with optional CUDA acceleration for NVIDIA GPUs.

**CRITICAL:** This project has complex dependencies and long build times. Always use the exact commands and timeouts specified below.

## Working Effectively

### Initial Setup (Required Every Time)
Run these commands in order to set up the development environment:

```bash
# 1. Install system dependencies (Linux) - takes 2-5 minutes
sudo apt-get update
sudo apt-get install -y \
  clang \
  cmake \
  ninja-build \
  pkg-config \
  libgtk-3-dev \
  liblzma-dev \
  libstdc++-12-dev \
  protobuf-compiler \
  libprotobuf-dev \
  libssl-dev \
  libfontconfig1-dev \
  libfreetype6-dev \
  libpipewire-0.3-dev \
  libspa-0.2-dev \
  pipewire-audio-client-libraries \
  libasound2-dev \
  libpulse-dev

# 2. Install Flutter (if not available)
# Use snap: sudo snap install flutter --classic
# OR download manually from https://flutter.dev/docs/get-started/install
# OR clone from GitHub: git clone -b stable https://github.com/flutter/flutter.git

# 3. Install Rust toolchain (if not available)
# Use rustup: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 4. Install LLVM 18 (required for FFI bindings)
# Use package manager or GitHub actions: KyleMayes/install-llvm-action@v2

# 5. For CUDA support (optional)
# Install CUDA Toolkit 12.4.0 from https://developer.nvidia.com/cuda-downloads
# Ensure nvcc is in PATH
```

### Build Process (NEVER CANCEL - CRITICAL TIMING)
Execute these commands in sequence. **Set timeouts to 60+ minutes for builds, 30+ minutes for tests**.

```bash
# 5. Flutter dependencies - takes ~2-5 minutes
flutter pub get

# 6. Dart code generation - takes ~5-10 minutes
dart run build_runner build --delete-conflicting-outputs

# 7. Rust dependencies - takes ~1-2 minutes  
cd rust && cargo update

# 8. Install Flutter Rust Bridge tools - takes ~3-5 minutes
cargo install cargo-expand flutter_rust_bridge_codegen

# 9. Generate bridge code - takes ~2-3 minutes
flutter_rust_bridge_codegen generate

# 10. Build the application - NEVER CANCEL: takes 15-45 minutes
# For Linux with NVIDIA:
scripts/build_linux.sh "true"
# For Linux without NVIDIA:
scripts/build_linux.sh "false"

# For Windows with NVIDIA:
scripts/build_windows.ps1 -EnableNvidia "true"
# For Windows without NVIDIA: 
scripts/build_windows.ps1 -EnableNvidia "false"
```

**CRITICAL BUILD WARNINGS:**
- **NEVER CANCEL builds or long-running commands** - they may take 45+ minutes
- **Always set timeouts to 60+ minutes** for build commands
- **Set timeouts to 30+ minutes** for test commands
- If a build appears to hang, wait at least 60 minutes before investigating

### Running Tests
```bash
# Unit tests - takes ~5-10 minutes. NEVER CANCEL.
flutter test

# Widget tests - takes ~2-5 minutes
flutter test test/widget_test.dart
```

### Running the Application
```bash
# Debug mode (development)
flutter run -d linux    # Linux
flutter run -d windows  # Windows  
flutter run -d macos    # macOS

# Release mode
# Built applications are located in:
# Linux: build/linux/x64/release/bundle[_with_cuda|_without_cuda]/fl_caption/
# Windows: build/windows/x64/runner/Release[_with_cuda|_without_cuda]/
# macOS: build/macos/Build/Products/Release/
```

## Validation Requirements

### Always Run These Before Committing
```bash
# Lint check - takes ~1-2 minutes
flutter analyze

# Format check - takes ~30 seconds
dart format --set-exit-if-changed .

# Rust checks - takes ~2-5 minutes
cd rust && cargo clippy -- -D warnings
cd rust && cargo fmt -- --check
```

### Manual Testing Scenarios
After making any changes, **ALWAYS test these complete user workflows**:

1. **Application Startup Test:**
   - Launch the application
   - Verify it opens without crashes
   - Check that the main UI loads properly

2. **Model Download Test:**
   - Click settings icon
   - Select a speech model
   - Click download button and verify progress
   - Wait for download completion (may take 10-30 minutes)

3. **Caption Generation Test:**
   - Set audio language and subtitle language
   - Configure LLM API settings if available
   - Start caption generation
   - Verify real-time subtitle display works
   - Test with different audio sources

4. **CUDA Test (if applicable):**
   - Enable CUDA acceleration in settings
   - Verify "Wait for Whisper" doesn't hang indefinitely
   - Test caption generation performance

## Build Artifacts and Locations

### Key Directories
- **Source code:** `lib/` (Flutter/Dart), `rust/src/` (Rust backend)
- **Build outputs:** `build/[platform]/` directories
- **Dependencies:** `rust_builder/` (Rust plugin integration)
- **Scripts:** `scripts/` (platform-specific build scripts)
- **Assets:** `assets/` (models, fonts, resources)

### Important Files
- `pubspec.yaml` - Flutter dependencies
- `rust/Cargo.toml` - Rust dependencies and features
- `flutter_rust_bridge.yaml` - Bridge configuration
- `analysis_options.yaml` - Dart linting rules

## Common Issues and Solutions

### Common Issues and Solutions

### Build Failures
- **"libpipewire-0.3 not found"** (Linux): Install `libpipewire-0.3-dev libspa-0.2-dev pipewire-audio-client-libraries`
- **"Failed to GET ort-rs binary"**: ONNX Runtime downloads binaries from cdn.pyke.io - requires internet access
- **"cl.exe not found"** (Windows): Ensure MSVC Build Tools are installed and NVCC_CCBIN is set
- **"Failed to execute nvcc"**: Install CUDA Toolkit 12.4.0 or disable NVIDIA features with `--no-default-features`
- **"Flutter not found"**: Use `flutter` command, not `dart pub`
- **"Protoc not found"**: Install protobuf-compiler package

### Network Dependencies
The build process requires internet access for:
- ONNX Runtime binary downloads (automatic)
- Hugging Face model downloads (runtime)
- Dart/Flutter package resolution
- Rust crate downloads

If internet access is restricted:
- Pre-download required binaries and set `ORT_LIB_LOCATION` environment variable
- Use HF_ENDPOINT environment variable for Hugging Face mirrors
- Set up local package mirrors for development

### Runtime Issues  
- **"Wait for Whisper" hangs**: Check CUDA installation or disable NVIDIA acceleration
- **Model download fails**: Set HF_ENDPOINT environment variable for mirror access
- **Audio not working**: Install required audio libraries (PipeWire, PulseAudio, ALSA)

### Environment Variables
- `ENABLE_NVIDIA=true/false` - Controls CUDA acceleration
- `HF_ENDPOINT` - Hugging Face mirror for model downloads (e.g., `https://hf-mirror.com`)
- `NVCC_CCBIN` - CUDA compiler path (Windows)
- `ORT_LIB_LOCATION` - Path to ONNX Runtime libraries (if not using auto-download)
- `ORT_SKIP_DOWNLOAD=1` - Skip automatic ONNX Runtime binary download

## Platform-Specific Notes

### Linux
- Requires GTK3, audio libraries (PipeWire/PulseAudio/ALSA)
- CUDA support via nvidia/cuda Docker or system installation
- Build outputs: `build/linux/x64/release/bundle[_with_cuda|_without_cuda]/fl_caption/`

### Windows  
- Requires MSVC Build Tools, Windows SDK
- CUDA Toolkit 12.4.0 for GPU acceleration
- Uses PowerShell build scripts
- Build outputs: `build/windows/x64/runner/Release[_with_cuda|_without_cuda]/`

### macOS
- Uses Metal acceleration instead of CUDA
- Requires Xcode command line tools
- Build outputs: `build/macos/Build/Products/Release/`

## Timing Expectations (Based on Validation)

**Development Setup:** 10-15 minutes total
**Rust Tool Installation:** 3-5 minutes (`cargo install flutter_rust_bridge_codegen`)
**Dependency Updates:** 20-30 seconds (`cargo update`)
**Full Clean Build:** 15-45 minutes (NEVER CANCEL)
**Incremental Build:** 5-15 minutes  
**Test Suite:** 5-15 minutes (NEVER CANCEL)
**Model Download:** 10-30 minutes (varies by model size and network speed)

## Alternative Build Configurations

### Building without CUDA/NVIDIA support
If CUDA is not available or causing issues:
```bash
# Disable NVIDIA features in Rust build
cd rust
cargo build --release --no-default-features

# Use non-CUDA build scripts
scripts/build_linux.sh "false"
scripts/build_windows.ps1 -EnableNvidia "false"
```

### Building with offline/restricted network
If internet access is limited:
```bash
# Set environment variables for offline builds
export ORT_SKIP_DOWNLOAD=1
export ORT_LIB_LOCATION="/path/to/onnxruntime"

# Use local package caches
flutter pub get --offline  # After initial online setup
cargo build --offline      # After initial online setup
```

## CI/CD Reference
See `.github/workflows/` for exact build steps used in continuous integration:
- `linux_build.yml` - Linux build process
- `windows_build.yml` - Windows build process  
- `macos_build.yml` - macOS build process

Always reference these workflows for the most up-to-date build commands and dependency versions.

## Quick Validation Commands
Use these commands to quickly verify the development environment:

```bash
# Verify tools are available
flutter --version        # Should show Flutter stable
dart --version           # Should show Dart 3.8+
cargo --version          # Should show Rust 1.89+
cmake --version          # Should show CMake 3.31+
protoc --version         # Should show protobuf 3.21+

# Verify audio libraries (Linux)
pkg-config --modversion libpipewire-0.3  # Should show version
pkg-config --modversion libpulse         # Should show version

# Quick dependency check
cd rust && cargo check --no-default-features  # Should compile without CUDA
flutter pub get                               # Should resolve dependencies
```

**Remember:** NEVER CANCEL long-running builds. Wait for completion even if it takes 45+ minutes.