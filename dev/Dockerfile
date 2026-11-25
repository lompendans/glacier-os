# Glacier OS dev/build environment: compiles floe, checks the Frost shell headless, builds the ISO.
FROM archlinux:latest
RUN pacman -Syu --noconfirm --needed \
      base-devel rust git \
      hyprland quickshell qt6-svg sway grim foot mako swaybg \
      inter-font ttf-jetbrains-mono papirus-icon-theme \
      librsvg archiso mesa grub freetype2 \
 && pacman -Scc --noconfirm
WORKDIR /src
