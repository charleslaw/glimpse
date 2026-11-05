#!/usr/bin/env python3
"""Install a checksum-pinned scanner in build/, without changing global tools."""
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent


def install_gitleaks():
    pin = json.loads((ROOT / "tools/security-tools.json").read_text())["gitleaks"]
    version = pin["version"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid pinned version")
    machine = {"arm64": "arm64", "aarch64": "arm64", "x86_64": "x64", "AMD64": "x64"}.get(platform.machine())
    platform_key = f"{platform.system().lower()}_{machine}"
    checksum = pin["archives"].get(platform_key)
    if not checksum:
        raise RuntimeError(f"Unsupported scanner platform: {platform_key}")
    folder = Path(os.environ.get("GLIMPSE_SECURITY_TOOLS_DIR", ROOT / "build/security-tools"))
    folder.mkdir(parents=True, exist_ok=True)
    name = f"gitleaks_{version}_{platform_key}.tar.gz"
    archive = folder / name
    if not archive.exists():
        url = f"https://github.com/gitleaks/gitleaks/releases/download/v{version}/{name}"
        with urllib.request.urlopen(url, timeout=60) as response:
            payload = response.read(50 * 1024 * 1024 + 1)
        if len(payload) > 50 * 1024 * 1024:
            raise RuntimeError("Scanner archive exceeds size limit")
        if hashlib.sha256(payload).hexdigest() != checksum:
            raise RuntimeError("Scanner archive checksum mismatch")
        archive.write_bytes(payload)
    payload = archive.read_bytes()
    if hashlib.sha256(payload).hexdigest() != checksum:
        raise RuntimeError("Cached scanner archive checksum mismatch")
    # Never extract arbitrary archive paths or links.
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:gz") as package:
        member = package.getmember("gitleaks")
        if not member.isfile() or member.size > 100 * 1024 * 1024:
            raise RuntimeError("Unexpected scanner archive contents")
        binary = package.extractfile(member)
        if binary is None:
            raise RuntimeError("Scanner binary missing")
        executable = folder / "gitleaks"
        with tempfile.NamedTemporaryFile(dir=folder, delete=False) as temporary:
            temporary.write(binary.read())
            temporary_path = Path(temporary.name)
        temporary_path.chmod(0o755)
        temporary_path.replace(executable)
    print(executable.resolve())


if __name__ == "__main__":
    install_gitleaks()
