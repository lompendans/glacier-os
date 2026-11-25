#!/usr/bin/env bash
# Build the Glacier OS live ISO. Runs inside the glacier-dev container (needs --privileged):
#   docker run --rm --privileged -v <glacier-os>:/src glacier-dev bash /src/iso/build.sh
# Output: /src/out/glacier-<date>-x86_64.iso
set -euo pipefail
SRC=/src
WORK=/tmp/glacier-build
OUT="$SRC/out"
P="$WORK/profile"
A="$P/airootfs"

rm -rf "$WORK"; mkdir -p "$WORK" "$OUT"

echo ":: starting from archiso's releng profile"
cp -r /usr/share/archiso/configs/releng "$P"

echo ":: packages"
grep -v '^\s*#' "$SRC/iso/packages.extra" | grep -v '^\s*$' >> "$P/packages.x86_64"
sort -u -o "$P/packages.x86_64" "$P/packages.x86_64"

echo ":: overlay"
# the live session only reaches the desktop through this file; refuse to build without it
[ -f "$SRC/iso/airootfs/etc/skel/.bash_profile" ] || { echo "missing iso/airootfs/etc/skel/.bash_profile (starts the desktop)" >&2; exit 1; }
cp -rT "$SRC/iso/airootfs" "$A"
rm -f "$A/etc/os-release"        # may arrive as a link from releng; replace with ours
cp "$SRC/iso/airootfs/etc/os-release" "$A/etc/os-release"

echo ":: floe"
cargo build --release --locked --manifest-path "$SRC/floe/Cargo.toml" --target-dir /tmp/floe-target
install -Dm755 /tmp/floe-target/release/floe "$A/usr/local/bin/floe"

echo ":: frost shell + configs"
mkdir -p "$A/usr/share/frost"
cp -r "$SRC/frost/quickshell" "$A/usr/share/frost/quickshell"
cp -r "$SRC/frost/greeter"    "$A/usr/share/frost/greeter"
install -Dm755 "$SRC/frost/bin/frost-qs"      "$A/usr/local/bin/frost-qs"
install -Dm755 "$SRC/frost/bin/frost-greeter" "$A/usr/local/bin/frost-greeter"
install -Dm644 "$SRC/frost/hypr/hyprland.lua"  "$A/etc/skel/.config/hypr/hyprland.lua"
install -Dm644 "$SRC/frost/foot/foot.ini"      "$A/etc/skel/.config/foot/foot.ini"
install -Dm644 "$SRC/frost/mako/config"        "$A/etc/skel/.config/mako/config"
mkdir -p "$A/usr/share/backgrounds/glacier"
rsvg-convert -w 2560 -h 1600 "$SRC/frost/wallpaper/glacier.svg" -o "$A/usr/share/backgrounds/glacier/glacier.png"

echo ":: installer"
install -Dm755 "$SRC/installer/glacier-install" "$A/usr/local/bin/glacier-install"
mkdir -p "$A/usr/share/glacier-installer"
cp "$SRC/installer/ui/"* "$A/usr/share/glacier-installer/"
install -Dm644 "$SRC/installer/glacier-installer.desktop" "$A/usr/share/applications/glacier-installer.desktop"

echo ":: services"
W="$A/etc/systemd/system"
# NetworkManager replaces releng's systemd-networkd + iwd (the Control Center uses nmcli)
rm -f "$W/multi-user.target.wants/systemd-networkd.service" \
      "$W/multi-user.target.wants/iwd.service" \
      "$W/sockets.target.wants/systemd-networkd.socket" \
      "$W/network-online.target.wants/systemd-networkd-wait-online.service" \
      "$W/systemd-networkd-wait-online.service.d/"*.conf 2>/dev/null || true
mkdir -p "$W/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$W/multi-user.target.wants/NetworkManager.service"
ln -sf /usr/lib/systemd/system/bluetooth.service      "$W/multi-user.target.wants/bluetooth.service"
ln -sf /etc/systemd/system/glacier-live-user.service  "$W/multi-user.target.wants/glacier-live-user.service"
# fetch package lists once online so floe search works in the live session
ln -sf /etc/systemd/system/glacier-refresh-db.service "$W/multi-user.target.wants/glacier-refresh-db.service"
mkdir -p "$W/network-online.target.wants"
ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service "$W/network-online.target.wants/NetworkManager-wait-online.service"

echo ":: branding"
sed -i \
  -e 's/^iso_name=.*/iso_name="glacier"/' \
  -e 's/^iso_version=.*/iso_version="$(date +%Y.%m.%d-%H%M)"/' \
  -e 's/^iso_label=.*/iso_label="GLACIER_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"/' \
  -e 's/^iso_publisher=.*/iso_publisher="Glacier OS"/' \
  -e 's/^iso_application=.*/iso_application="Glacier OS Live"/' \
  "$P/profiledef.sh"
# file permissions for our executables / sudoers
sed -i 's|^file_permissions=(|file_permissions=(\n  ["/usr/local/bin/floe"]="0:0:755"\n  ["/usr/local/bin/glacier-live-setup"]="0:0:755"\n  ["/usr/local/bin/glacier-install"]="0:0:755"\n  ["/usr/local/bin/frost-qs"]="0:0:755"\n  ["/usr/local/bin/frost-greeter"]="0:0:755"\n  ["/etc/sudoers.d/glacier-live"]="0:0:440"|' "$P/profiledef.sh"
# boot splash (BIOS menu)
rsvg-convert -w 640 -h 480 "$SRC/frost/wallpaper/splash.svg" -o "$P/syslinux/splash.png"
# 2 GiB of RAM-backed write space so floe can install packages in the live session
grep -rl "archisobasedir=%INSTALL_DIR%" "$P/grub" "$P/syslinux" "$P/efiboot" | xargs -r sed -i 's/archisobasedir=%INSTALL_DIR%/& cow_spacesize=2G/'
# boot menu titles
grep -rl "Arch Linux" "$P/grub" "$P/syslinux" "$P/efiboot" 2>/dev/null | xargs -r sed -i 's/Arch Linux install medium/Glacier OS live/g; s/Arch Linux/Glacier OS/g'

echo ":: bootloader theme"
# BIOS (syslinux): Glacier accent colours over the splash
sed -i \
  -e 's/^MENU COLOR border .*/MENU COLOR border       30;44   #30ffffff #00000000 none/' \
  -e 's/^MENU COLOR title .*/MENU COLOR title        1;36;44 #ff5ac8fa #00000000 none/' \
  -e 's/^MENU COLOR sel .*/MENU COLOR sel          7;37;40 #ffffffff #605ac8fa none/' \
  -e 's/^MENU COLOR unsel .*/MENU COLOR unsel        37;44   #c0e8ecf8 #00000000 none/' \
  "$P/syslinux/archiso_head.cfg"
# UEFI: GRUB with the Glacier glass theme instead of plain-text systemd-boot
sed -i "s/'uefi.systemd-boot'/'uefi.grub'/" "$P/profiledef.sh"
grep -q "'uefi.grub'" "$P/profiledef.sh" || { echo "could not switch UEFI boot mode to GRUB" >&2; exit 1; }
bash "$SRC/frost/grub/make-theme.sh" "$P/grub/themes/glacier"
cat >> "$P/grub/grub.cfg" <<'EOF'

# --- Glacier theme ---
# (on the UEFI image ${prefix} is GRUB's built-in memdisk; the theme lives on the ISO, which is $root)
insmod all_video
insmod gfxterm
insmod gfxmenu
insmod png
loadfont "($root)/boot/grub/themes/glacier/glacier-16.pf2"
loadfont "($root)/boot/grub/themes/glacier/glacier-20.pf2"
loadfont "($root)/boot/grub/themes/glacier/glacier-bold-20.pf2"
set gfxmode=auto
terminal_output gfxterm
set theme="($root)/boot/grub/themes/glacier/theme.txt"
EOF
# the installer puts the same theme on installed systems
mkdir -p "$A/usr/share/grub/themes"
cp -r "$P/grub/themes/glacier" "$A/usr/share/grub/themes/glacier"

echo ":: mkarchiso"
mkarchiso -v -w "$WORK/work" -o "$WORK/iso" "$P"
cp "$WORK"/iso/*.iso "$OUT/"
ls -lh "$OUT"/*.iso
