"""Packs fl_caption releases into dist/. Every archive unpacks into the same
fl_caption/ folder, as ImmersiveVR's releases do:

  fl_caption-v<ver>-<os>-x64.(zip|tar.gz)          the program, with the CPU
      ONNX Runtime (runtime/ort-cpu): speech on the CPU and translation
      through an API work out of the box
  fl_caption-runtime-cuda-v<ver>-<os>-x64.(zip|tar.gz)
      runtime/ort: ONNX Runtime 1.31 (CUDA 12 build), the CUDA 12.8 runtime
      and cuBLAS, cuDNN 9 -- the GPU models need it (NVIDIA GPU, driver 550+)

Models are not packed: the app downloads them (the ModaLeap repositories
local-multimodal-infra publishes), or imports exported directories.

Before packing:
  python scripts/fetch_onnxruntime.py
  flutter build windows --release        (or: flutter build linux --release)

The CUDA libraries come from NVIDIA's wheels on PyPI (pinned, SHA-256
checked); --wheel-dir names a directory that may hold them already.

  python scripts/package_release.py [--version 0.2.0] [--only program,runtime]
      [--wheel-dir DIR] [--pypi-mirror https://pypi.tuna.tsinghua.edu.cn]
"""

from __future__ import annotations

import argparse
import hashlib
import io
import os
import platform
import sys
import tarfile
import time
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
TOP = "fl_caption"
WINDOWS = platform.system() == "Windows"

PYPI_FILES = "https://files.pythonhosted.org"
# (url path under files.pythonhosted.org, sha256, member prefix, file suffixes)
WHEELS = {
    True: [  # Windows
        (
            "/packages/30/a5/a515b7600ad361ea14bfa13fb4d6687abf500adc270f19e89849c0590492/"
            "nvidia_cuda_runtime_cu12-12.8.90-py3-none-win_amd64.whl",
            "c0c6027f01505bfed6c3b21ec546f69c687689aad5f1a377554bc6ca4aa993a8",
            "nvidia/cuda_runtime/bin/",
            ("cudart64_12.dll",),
        ),
        (
            "/packages/70/61/7d7b3c70186fb651d0fbd35b01dbfc8e755f69fd58f817f3d0f642df20c3/"
            "nvidia_cublas_cu12-12.8.4.1-py3-none-win_amd64.whl",
            "47e9b82132fa8d2b4944e708049229601448aaad7e6f296f630f2d1a32de35af",
            "nvidia/cublas/bin/",
            ("cublas64_12.dll", "cublasLt64_12.dll"),
        ),
        (
            "/packages/aa/38/f856579877f7c1c5066e61182e7de7bc27bf35a78c8d1b0fa592e6985bc4/"
            "nvidia_cudnn_cu12-9.27.0.42-py3-none-win_amd64.whl",
            "06e9b0026f3bad97d2b58666330fabec04fe1672f776661ecb0ce0029c27f142",
            "nvidia/cudnn/bin/",
            ("64_9.dll",),
        ),
    ],
    False: [  # Linux
        (
            "/packages/0d/9b/a997b638fcd068ad6e4d53b8551a7d30fe8b404d6f1804abf1df69838932/"
            "nvidia_cuda_runtime_cu12-12.8.90-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl",
            "adade8dcbd0edf427b7204d480d6066d33902cab2a4707dcfc48a2d0fd44ab90",
            "nvidia/cuda_runtime/lib/",
            ("libcudart.so.12",),
        ),
        (
            "/packages/dc/61/e24b560ab2e2eaeb3c839129175fb330dfcfc29e5203196e5541a4c44682/"
            "nvidia_cublas_cu12-12.8.4.1-py3-none-manylinux_2_27_x86_64.whl",
            "8ac4e771d5a348c551b2a426eda6193c19aa630236b418086020df5ba9667142",
            "nvidia/cublas/lib/",
            ("libcublas.so.12", "libcublasLt.so.12"),
        ),
        (
            "/packages/65/e4/c5a205d48ff00ed8b27882bb45d338d8138e976c76385f328a326bbfaeda/"
            "nvidia_cudnn_cu12-9.27.0.42-py3-none-manylinux_2_27_x86_64.whl",
            "0a4aa3a7d2264256506c6857fc41fc0c499982f78d70195b1cfcc9055c1957cd",
            "nvidia/cudnn/lib/",
            (".so.9",),
        ),
    ],
}

# The MSVC runtime the program, the Rust library and ONNX Runtime link
# against, app-local.
VC_RUNTIME = ["vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll", "msvcp140_atomic_wait.dll"]

RUNTIME_NOTICE = """fl_caption GPU runtime (unpack into the fl_caption folder)

runtime/ort/ holds third-party libraries, redistributed under their licenses:
- ONNX Runtime 1.31 (MIT): LICENSE-onnxruntime.txt, ThirdPartyNotices-onnxruntime.txt
- NVIDIA CUDA 12 runtime and cuBLAS: NVIDIA CUDA Toolkit EULA,
  https://docs.nvidia.com/cuda/eula/
- NVIDIA cuDNN 9: NVIDIA cuDNN Software License Agreement,
  https://docs.nvidia.com/deeplearning/cudnn/latest/reference/eula.html
"""


class Archive:
    """A zip on Windows, a tar.gz on Linux (keeps file modes and links)."""

    def __init__(self, stem: str):
        DIST.mkdir(parents=True, exist_ok=True)
        self.path = DIST / (f"{stem}.zip" if WINDOWS else f"{stem}.tar.gz")
        self.path.unlink(missing_ok=True)
        self.raw = 0
        if WINDOWS:
            self.zip = zipfile.ZipFile(self.path, "w", zipfile.ZIP_DEFLATED, compresslevel=6)
        else:
            self.tar = tarfile.open(self.path, "w:gz", compresslevel=6)

    def add(self, source: Path, name: str):
        self.raw += source.stat().st_size
        if WINDOWS:
            self.zip.write(source, f"{TOP}/{name}")
        else:
            self.tar.add(source, f"{TOP}/{name}", recursive=False)

    def data(self, name: str, content: bytes):
        self.raw += len(content)
        if WINDOWS:
            self.zip.writestr(f"{TOP}/{name}", content)
        else:
            info = tarfile.TarInfo(f"{TOP}/{name}")
            info.size = len(content)
            info.mode = 0o755 if name.endswith(".so") or ".so." in name else 0o644
            info.mtime = int(time.time())
            self.tar.addfile(info, io.BytesIO(content))

    def tree(self, source: Path, prefix: str = ""):
        for root, _, files in os.walk(source):
            for file in sorted(files):
                path = Path(root) / file
                self.add(path, prefix + path.relative_to(source).as_posix())

    def close(self):
        (self.zip if WINDOWS else self.tar).close()
        size = self.path.stat().st_size
        print(f"{self.path.name}: {self.raw / 2**20:,.0f} MB -> {size / 2**20:,.0f} MB")
        if size >= 2 * 2**30:
            sys.exit(f"{self.path.name} is over GitHub's 2 GB asset limit")


def program(version: str):
    if WINDOWS:
        build = ROOT / "build" / "windows" / "x64" / "runner" / "Release"
        exe = build / "fl_caption.exe"
    else:
        build = ROOT / "build" / "linux" / "x64" / "release" / "bundle"
        exe = build / "fl_caption"
    if not exe.is_file():
        sys.exit(f"build the app first: flutter build {'windows' if WINDOWS else 'linux'} --release")
    cpu = ROOT / "runtime" / "ort-cpu"
    if not cpu.is_dir():
        sys.exit("run python scripts/fetch_onnxruntime.py first (runtime/ort-cpu)")
    out = Archive(f"fl_caption-v{version}-{'windows' if WINDOWS else 'linux'}-x64")
    out.tree(build)
    out.tree(cpu, "runtime/ort-cpu/")
    if WINDOWS:
        system = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"
        for name in VC_RUNTIME:
            path = system / name
            if not path.is_file():
                sys.exit(f"{path} is missing (install the Visual C++ redistributable)")
            out.add(path, name)
    out.add(ROOT / "LICENSE", "LICENSE")
    out.close()


def wheel(url_path: str, sha256: str, wheel_dir: Path | None, cache: Path, mirror: str | None) -> zipfile.ZipFile:
    name = url_path.rsplit("/", 1)[1]
    for directory in [wheel_dir, cache]:
        if directory and (directory / name).is_file():
            data = (directory / name).read_bytes()
            if hashlib.sha256(data).hexdigest() == sha256:
                return zipfile.ZipFile(io.BytesIO(data))
    url = (mirror.rstrip("/") if mirror else PYPI_FILES) + url_path
    print(f"[cuda] downloading {url}")
    with urllib.request.urlopen(url, timeout=1800) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != sha256:
        sys.exit(f"SHA-256 mismatch for {name}")
    cache.mkdir(parents=True, exist_ok=True)
    (cache / name).write_bytes(data)
    return zipfile.ZipFile(io.BytesIO(data))


def runtime(version: str, wheel_dir: Path | None, mirror: str | None):
    ort = ROOT / "runtime" / "ort"
    provider = "onnxruntime_providers_cuda.dll" if WINDOWS else "libonnxruntime_providers_cuda.so"
    if not (ort / provider).is_file():
        sys.exit("run python scripts/fetch_onnxruntime.py first (runtime/ort, the CUDA 12 build)")
    out = Archive(f"fl_caption-runtime-cuda-v{version}-{'windows' if WINDOWS else 'linux'}-x64")
    for path in sorted(ort.iterdir()):
        if path.is_file() and path.suffix not in (".lib", ".pdb"):
            out.add(path, f"runtime/ort/{path.name}")
    cache = ROOT / "build" / "cuda-cache"
    for url_path, sha256, prefix, suffixes in WHEELS[WINDOWS]:
        archive = wheel(url_path, sha256, wheel_dir, cache, mirror)
        found = 0
        for member in archive.namelist():
            base = member.rsplit("/", 1)[-1]
            if member.startswith(prefix) and any(base.endswith(s) for s in suffixes):
                out.data(f"runtime/ort/{base}", archive.read(member))
                found += 1
        if not found:
            sys.exit(f"no {suffixes} under {prefix} in {url_path.rsplit('/', 1)[1]}")
    out.data("runtime/ort/NOTICE.txt", RUNTIME_NOTICE.encode())
    out.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", default="0.2.0")
    parser.add_argument("--only", default="program,runtime", help="comma-separated: program, runtime")
    parser.add_argument("--wheel-dir", type=Path, default=None, help="a directory that may hold the NVIDIA wheels")
    parser.add_argument("--pypi-mirror", default=None, help="serves /packages/... as files.pythonhosted.org does")
    args = parser.parse_args()
    for step in args.only.split(","):
        if step == "program":
            program(args.version)
        elif step == "runtime":
            runtime(args.version, args.wheel_dir, args.pypi_mirror)
        else:
            sys.exit(f"unknown package {step!r}: program or runtime")


if __name__ == "__main__":
    main()
