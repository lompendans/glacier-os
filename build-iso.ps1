# Build the Glacier OS ISO on Windows using Docker Desktop.
# Usage:  .\build-iso.ps1        -> out\glacier-YYYY.MM.DD-x86_64.iso
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
docker build -t glacier-dev "$root\dev"
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }
# glacier-pkgcache keeps downloaded packages between builds (faster, and survives a flaky mirror)
docker run --rm --privileged -v "${root}:/src" -v glacier-pkgcache:/var/cache/pacman/pkg glacier-dev bash /src/iso/build.sh
if ($LASTEXITCODE -ne 0) { throw "ISO build failed" }
Get-ChildItem "$root\out\*.iso" | Sort-Object LastWriteTime | Select-Object -Last 1
