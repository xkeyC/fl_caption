"""Fetches the pinned ONNX Runtime fl_caption loads at run time.

The Rust engine loads ONNX Runtime dynamically (ort `load-dynamic`), so the
library is needed to run, not to build. This downloads the pinned 1.31.0
release archives from GitHub, checks their SHA-256 and copies the libraries:

- runtime/ort-cpu/: the CPU build (ships inside the program package);
- runtime/ort/:     the CUDA 12 build (built with CUDA 12.8), the GPU runtime
                    package. It needs a CUDA 12.8+ runtime (cudart, cuBLAS,
                    cuFFT) and cuDNN 9 beside it or on the library path:
                    `scripts/package_release.py` collects them from the
                    `lib=` directories of runtime/runtime.txt.

    python scripts/fetch_onnxruntime.py [--cpu-only] [--cache DIR]

Pins taken from local-multimodal-infra/scripts/local/fetch_onnxruntime.py.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import platform
import shutil
import sys
import tarfile
import time
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path

ORT_VERSION = "1.31.0"
ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class Package:
    url: str
    sha256: str
    # Member path suffixes to extract (matched against archive names).
    members: tuple[str, ...]


GITHUB = f"https://github.com/microsoft/onnxruntime/releases/download/v{ORT_VERSION}"
PACKAGES = {
    ("Windows", "cuda"): Package(
        f"{GITHUB}/onnxruntime-win-x64-gpu_cuda12-{ORT_VERSION}.zip",
        "fa79097fa478961cbd31c297671ac169eb0d3f1dfdc9e8481e091850f8c4810b",
        (
            "/lib/onnxruntime.dll",
            "/lib/onnxruntime_providers_shared.dll",
            "/lib/onnxruntime_providers_cuda.dll",
        ),
    ),
    ("Windows", "cpu"): Package(
        f"{GITHUB}/onnxruntime-win-x64-{ORT_VERSION}.zip",
        "3958d8a44984160692c1b4ffd0de3cb48f8c39f9d34bb31e433db06e30b82195",
        ("/lib/onnxruntime.dll", "/lib/onnxruntime_providers_shared.dll"),
    ),
    ("Linux", "cuda"): Package(
        f"{GITHUB}/onnxruntime-linux-x64-gpu_cuda12-{ORT_VERSION}.tgz",
        "62d3af5269af2143b5d37494337573f1ffb8885f3ad7477ae0cb1cc79c8dedfd",
        (
            f"/lib/libonnxruntime.so.{ORT_VERSION}",
            "/lib/libonnxruntime_providers_shared.so",
            "/lib/libonnxruntime_providers_cuda.so",
        ),
    ),
    ("Linux", "cpu"): Package(
        f"{GITHUB}/onnxruntime-linux-x64-{ORT_VERSION}.tgz",
        "cc5c72baf5ae5c8238a6841f0897227be2d02826b9cf98eaf02fdefaeeb03a57",
        (f"/lib/libonnxruntime.so.{ORT_VERSION}",),
    ),
}


def download(package: Package, cache: Path) -> bytes:
    path = cache / package.url.rsplit("/", 1)[1]
    if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == package.sha256:
        return path.read_bytes()
    cache.mkdir(parents=True, exist_ok=True)
    data = b""
    for attempt in range(1, 7):
        print(f"[ort] downloading {package.url}")
        try:
            with urllib.request.urlopen(package.url, timeout=600) as response:
                data = response.read()
            break
        except OSError as exc:
            if attempt == 6:
                raise SystemExit(f"[ort] download failed: {exc}") from exc
            print(f"[ort] retrying in {5 * attempt} s after: {exc}")
            time.sleep(5 * attempt)
    digest = hashlib.sha256(data).hexdigest()
    if digest != package.sha256:
        raise SystemExit(f"[ort] SHA-256 mismatch for {package.url}: {digest} != {package.sha256}")
    path.write_bytes(data)
    return data


def extract(package: Package, data: bytes) -> dict[str, bytes]:
    files: dict[str, bytes] = {}
    if package.url.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for name in archive.namelist():
                if any(name.endswith(member) for member in package.members):
                    files[Path(name).name] = archive.read(name)
    else:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            for member in archive.getmembers():
                if member.isfile() and any(member.name.endswith(m) for m in package.members):
                    files[Path(member.name).name] = archive.extractfile(member).read()
    # The license texts travel with the libraries.
    if package.url.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for name in archive.namelist():
                if name.endswith(("/LICENSE", "/ThirdPartyNotices.txt")) and name.count("/") == 1:
                    files[f"{Path(name).stem}-onnxruntime.txt"] = archive.read(name)
    else:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            for member in archive.getmembers():
                if member.isfile() and member.name.endswith(("/LICENSE", "/ThirdPartyNotices.txt")) and member.name.count("/") == 1:
                    files[f"{Path(member.name).stem}-onnxruntime.txt"] = archive.extractfile(member).read()
    missing = [m for m in package.members if Path(m).name not in files]
    if missing:
        raise SystemExit(f"[ort] {package.url} lacks {missing}")
    return files


def install(files: dict[str, bytes], dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        target = dest / name
        if target.is_symlink() or target.exists():
            target.unlink()
        target.write_bytes(data)
        print(f"[ort] {target}")
    if f"libonnxruntime.so.{ORT_VERSION}" in files:
        # The loader asks for libonnxruntime.so.
        for alias in ("libonnxruntime.so", "libonnxruntime.so.1"):
            link = dest / alias
            if link.is_symlink() or link.exists():
                link.unlink()
            shutil.copyfile(dest / f"libonnxruntime.so.{ORT_VERSION}", link)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cpu-only", action="store_true", help="only the CPU build (runtime/ort-cpu)")
    parser.add_argument("--cache", type=Path, default=ROOT / "build" / "ort-cache", help="download cache")
    args = parser.parse_args(argv)
    system = platform.system()
    if platform.machine().lower() not in ("amd64", "x86_64") or (system, "cpu") not in PACKAGES:
        print(f"[ort] no pinned ONNX Runtime for {system} {platform.machine()}", file=sys.stderr)
        return 1
    builds = [("cpu", ROOT / "runtime" / "ort-cpu")]
    if not args.cpu_only:
        builds.append(("cuda", ROOT / "runtime" / "ort"))
    for kind, dest in builds:
        package = PACKAGES[(system, kind)]
        install(extract(package, download(package, args.cache)), dest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
