# Boot the newest Glacier OS ISO in QEMU (UEFI not required; BIOS boot via syslinux).
# Usage:  .\run-qemu.ps1 [-Iso path] [-NoAccel]
param([string]$Iso, [switch]$NoAccel)
$ErrorActionPreference = "Stop"
$qemu = "C:\Program Files\qemu\qemu-system-x86_64.exe"
if (-not $Iso) { $Iso = (Get-ChildItem "$PSScriptRoot\out\*.iso" | Sort-Object LastWriteTime | Select-Object -Last 1).FullName }
if (-not $Iso) { throw "no ISO in out\ - run .\build-iso.ps1 first" }
$accel = if ($NoAccel) { @("-accel", "tcg") } else { @("-accel", "whpx,kernel-irqchip=off", "-accel", "tcg") }
& $qemu @accel -m 4096 -smp 4 -cpu qemu64,+ssse3,+sse4.1,+sse4.2,+popcnt `
    -device virtio-vga -display sdl `
    -device qemu-xhci -device usb-tablet `
    -nic user,model=virtio-net-pci `
    -cdrom $Iso -boot d
