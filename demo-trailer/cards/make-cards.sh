#!/usr/bin/env bash
# Render the Live Demo trailer's title cards and captions (1600x900 PNGs) from SVG.
# Runs in the glacier-dev container:  bash /src/demo-trailer/cards/make-cards.sh /src/demo-trailer/build/cards
set -euo pipefail
OUT="${1:?usage: make-cards.sh <outdir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$OUT"
rsvg-convert -w 1600 -h 1000 "$HERE/../../frost/wallpaper/glacier.svg" -o "$T/wall.png"

logo='<rect x="-46" y="-46" width="92" height="92" rx="26" fill="url(#lg)"/><g transform="translate(-33 -33) scale(2.75)" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2.5 19L9 7.5l3.2 5L15 8.5 21.5 19z"/><path d="M7.2 10.7l1.8 1.3 1.4-1.6"/></g>'
defs='<defs><linearGradient id="lg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5ac8fa"/><stop offset="1" stop-color="#8a7dff"/></linearGradient></defs>'

card() { # name title subtitle
  cat > "$T/$1.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900" viewBox="0 0 1600 900">$defs
  <image href="wall.png" width="1600" height="1000" y="-50"/>
  <rect width="1600" height="900" fill="#05070f" fill-opacity=".25"/>
  <rect x="400" y="250" width="800" height="400" rx="44" fill="#ffffff" fill-opacity=".12" stroke="#ffffff" stroke-opacity=".45"/>
  <rect x="444" y="251" width="712" height="1.5" fill="#ffffff" fill-opacity=".8"/>
  <g transform="translate(800 375)">$logo</g>
  <text x="800" y="505" text-anchor="middle" font-family="Inter" font-weight="800" font-size="76" fill="#fff" letter-spacing="-2">$2</text>
  <text x="800" y="565" text-anchor="middle" font-family="Inter" font-weight="500" font-size="28" fill="#ffffff" fill-opacity=".78">$3</text>
</svg>
SVG
  rsvg-convert "$T/$1.svg" -o "$OUT/$1.png"
}
caption() { # name text  (transparent lower third)
  local w=$(( ${#2} * 15 + 100 ))
  cat > "$T/$1.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900" viewBox="0 0 1600 900">$defs
  <rect x="48" y="770" width="$w" height="76" rx="38" fill="#0e1224" fill-opacity=".55" stroke="#ffffff" stroke-opacity=".4"/>
  <rect x="80" y="771" width="$(( w - 64 ))" height="1.5" fill="#ffffff" fill-opacity=".7"/>
  <circle cx="90" cy="808" r="9" fill="url(#lg)"/>
  <text x="114" y="818" font-family="Inter" font-weight="700" font-size="28" fill="#fff">$2</text>
</svg>
SVG
  rsvg-convert "$T/$1.svg" -o "$OUT/$1.png"
}

card intro "Glacier OS" "Live Demo · recorded on the real system"
card outro "Glacier OS 0.1" "Frost desktop · floe · Glacier installer"
caption c-boot "Branded boot menu"
caption c-desktop "The Frost liquid-glass desktop"
caption c-launcher "Launcher: apps and packages in one search"
caption c-floe "floe: pacman with generations and rollback"
caption c-cc "Control Center"
caption c-installer "A real installer — offline, BIOS + UEFI"
caption c-grub "Themed GRUB on the installed system"
caption c-firstboot "First boot of the installed system"
echo "cards written to $OUT"
