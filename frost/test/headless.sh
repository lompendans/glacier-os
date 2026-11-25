#!/usr/bin/env bash
# Render the Frost shell without a GPU or display and take screenshots.
# Runs in the glacier-dev container:
#   docker run --rm -v <glacier-os>:/src glacier-dev bash /src/frost/test/headless.sh
# Uses headless sway (software renderer) as the compositor, so there is no blur here —
# this checks that the QML loads without errors and the layout renders.
# Output: /src/out/shots/*.png and /src/out/shots/qs.log
set -euo pipefail
OUT=/src/out/shots
mkdir -p "$OUT"; rm -f "$OUT"/*.png "$OUT"/qs.log

# floe for the package count / package search
CARGO_TARGET_DIR=/tmp/ft cargo build -q --release --locked --manifest-path /src/floe/Cargo.toml
install -m755 /tmp/ft/release/floe /usr/local/bin/floe
rsvg-convert -w 1600 -h 1000 /src/frost/wallpaper/glacier.svg -o /tmp/wall.png

id t >/dev/null 2>&1 || useradd -m t
# sway ships with cap_sys_nice, which Docker does not grant; drop it (container only)
setcap -r /usr/bin/sway 2>/dev/null || true
cat > /tmp/run.sh <<'EOF'
set -u
export XDG_RUNTIME_DIR=/tmp/rt; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
export QT_QUICK_CONTROLS_STYLE=Basic QT_QPA_PLATFORM=wayland
cat > /tmp/sway.conf <<'S'
output HEADLESS-1 resolution 1600x1000 bg /tmp/wall.png fill
default_border none
S
sway -c /tmp/sway.conf >/tmp/sway.log 2>&1 &
for i in $(seq 50); do ls $XDG_RUNTIME_DIR/wayland-* >/dev/null 2>&1 && break; sleep 0.2; done
export WAYLAND_DISPLAY=$(basename $(ls $XDG_RUNTIME_DIR/wayland-* | grep -v lock | head -1))
QS="qs -p /src/frost/quickshell"
$QS >/tmp/qs.log 2>&1 &
sleep 6
grim /tmp/desktop.png
$QS ipc call frost launcher; sleep 2; grim /tmp/launcher.png
$QS ipc call frost launcher; sleep 1
$QS ipc call frost packages; sleep 2; grim /tmp/packages.png
$QS ipc call frost packages; sleep 1
$QS ipc call frost search fire; sleep 3; grim /tmp/search.png
$QS ipc call frost launcher; sleep 1
$QS ipc call frost controlCenter; sleep 2; grim /tmp/controlcenter.png
$QS ipc call frost controlCenter; sleep 1
# installer UI: render each page
IN="qs -p /src/installer/ui"
$IN >/tmp/installer.log 2>&1 &
sleep 5
for p in 0 1 2 3 4; do $IN ipc call installer goto $p; sleep 1.5; grim /tmp/installer-$p.png; done
pkill -f "installer/ui" || true
sleep 1
# greeter UI: render the Frost login screen
qs -p /src/frost/greeter >/tmp/greeter.log 2>&1 &
sleep 5
grim /tmp/greeter.png
EOF
su t -c "bash /tmp/run.sh" || true
cp /tmp/*.png "$OUT"/ 2>/dev/null || true
cp /tmp/qs.log /tmp/installer.log /tmp/greeter.log "$OUT"/ 2>/dev/null || true
for log in qs installer greeter; do
  echo "---- $log log (warnings/errors) ----"
  grep -i -E "warn|error|fail|cannot|not a type|undefined|unavailable" "$OUT/$log.log" || echo "(none)"
done
ls -la "$OUT"
