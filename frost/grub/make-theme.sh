#!/usr/bin/env bash
# Generate the Glacier GRUB theme (liquid-glass menu) into <outdir>.
# Needs: rsvg-convert, grub-mkfont, Inter font. Used by iso/build.sh for the live ISO
# (UEFI) and installed into the live system for the installer.
#   usage: make-theme.sh <outdir>
set -euo pipefail
OUT="${1:?usage: make-theme.sh <outdir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
FONT=/usr/share/fonts/inter/InterVariable.ttf
mkdir -p "$OUT"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# background: the wallpaper with the Glacier logo + name on top
# (librsvg only loads images next to the SVG, so render the wallpaper into the temp dir first)
rsvg-convert -w 1920 -h 1200 "$HERE/../wallpaper/glacier.svg" -o "$T/wall.png"
cp "$HERE/background.svg" "$T/background.svg"
rsvg-convert -w 1920 -h 1080 "$T/background.svg" -o "$OUT/background.png"

# 9-slice glass panels: render each slice of a (3c)x(3c) rounded rectangle, c = corner size.
# GRUB draws the border slices *outside* the item, so keep c small for the selection box.
slices() { # name fill-opacity stroke-opacity radius corner
  local name=$1 fo=$2 so=$3 r=$4 c=$5
  local -A pos=([nw]="0 0" [n]="$c 0" [ne]="$((2*c)) 0" [w]="0 $c" [c]="$c $c" [e]="$((2*c)) $c" [sw]="0 $((2*c))" [s]="$c $((2*c))" [se]="$((2*c)) $((2*c))")
  for k in "${!pos[@]}"; do
    read -r x y <<<"${pos[$k]}"
    cat > "$T/s.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="$c" height="$c" viewBox="$x $y $c $c">
  <rect x="0.5" y="0.5" width="$((3*c-1))" height="$((3*c-1))" rx="$r" fill="#ffffff" fill-opacity="$fo" stroke="#ffffff" stroke-opacity="$so"/>
</svg>
EOF
    rsvg-convert "$T/s.svg" -o "$OUT/${name}_${k}.png"
  done
}
slices menu   0.13 0.38 16 16
slices select 0.22 0.55 8 8
slices term   0    0    2 4      # invisible box for GRUB's text terminal ("Booting …")

# fonts (GRUB needs bitmap .pf2 fonts)
# (grub-mkfont warns about OpenType features GRUB doesn't use; hide only those lines)
mkfont() { grub-mkfont "$@" 2> >(grep -v "unsupported font feature" >&2); }
mkfont -n "Glacier" -s 16 -o "$OUT/glacier-16.pf2" "$FONT"
mkfont -n "Glacier" -s 20 -o "$OUT/glacier-20.pf2" "$FONT"
mkfont -n "Glacier" -s 20 -b -o "$OUT/glacier-bold-20.pf2" "$FONT"

cp "$HERE/theme.txt" "$OUT/theme.txt"
echo "theme written to $OUT"
