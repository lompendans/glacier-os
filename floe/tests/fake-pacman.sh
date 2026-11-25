#!/usr/bin/env bash
# Minimal pacman stand-in for floe's end-to-end tests.
#   $FAKE_DB    installed packages: "name version explicit(1|0)" per line
#   $FAKE_REPO  repository: "repo name version description..." per line
#   $FAKE_DEPS  dependencies: "package dependency" per line
#   $FLOE_CACHE package cache dir (downloads are "stored" here like /var/cache/pacman/pkg)
# Mirrors the pacman behaviour floe relies on: new installs are explicit, reinstalls and
# -U up/downgrades keep the existing install reason, -Rs drops orphaned dependencies.
set -euo pipefail
db="${FAKE_DB:?}"; repo="${FAKE_REPO:?}"; deps="${FAKE_DEPS:?}"; cache="${FLOE_CACHE:?}"
touch "$db" "$deps"; mkdir -p "$cache"
op="${1:?}"; shift
flags=" "; pk=()
for a in "$@"; do case "$a" in -*) flags+="$a ";; *) pk+=("$a");; esac; done

has()      { grep -q "^$1 " "$db"; }
reason()   { awk -v n="$1" '$1==n{print $3}' "$db"; }
repo_ver() { awk -v n="$1" '$2==n{print $3}' "$repo"; }
deps_of()  { awk -v n="$1" '$1==n{print $2}' "$deps"; }
set_pkg()  { { grep -v "^$1 " "$db" || true; echo "$1 $2 $3"; } | sort > "$db.t"; mv "$db.t" "$db"; }
del_pkg()  { { grep -v "^$1 " "$db" || true; } > "$db.t"; mv "$db.t" "$db"; }
fetch()    { touch "$cache/$1-$2-x86_64.pkg.tar.zst"; }
install_one() { # name explicit-if-new
  local n="$1" v; v="$(repo_ver "$n")"
  [ -n "$v" ] || { echo "error: target not found: $n" >&2; exit 1; }
  local d; for d in $(deps_of "$n"); do has "$d" || install_one "$d" 0; done
  fetch "$n" "$v"
  if has "$n"; then set_pkg "$n" "$v" "$(reason "$n")"; else set_pkg "$n" "$v" "$2"; fi
}

case "$op" in
  -Q)  awk '{print $1, $2}' "$db" ;;
  -Qe) awk '$3==1{print $1, $2}' "$db" ;;
  -Qi|-Si) echo "Name            : ${pk[0]}" ;;
  -Ss)
    # $db.nosync simulates a fresh system whose package lists were never downloaded
    if [ -e "$db.nosync" ]; then
      echo "warning: database file for 'core' does not exist (use '-Sy' to download)" >&2; exit 1
    fi
    q="${pk[*]:-}"
    { grep -i -- "$q" "$repo" || true; } | while read -r r n v d; do
      tag=""; has "$n" && tag=" [installed]"
      echo "$r/$n $v$tag"; echo "    $d"
    done ;;
  -Sy) rm -f "$db.nosync" ;;
  -S|-Syu)
    for n in "${pk[@]}"; do [ -n "$(repo_ver "$n")" ] || { echo "error: target not found: $n" >&2; exit 1; }; done
    if [ "$op" = "-Syu" ]; then
      rm -f "$db.nosync"
      while read -r n v r; do
        nv="$(repo_ver "$n")"
        if [ -n "$nv" ] && [ "$nv" != "$v" ]; then fetch "$n" "$nv"; set_pkg "$n" "$nv" "$r"; fi
      done < <(cat "$db")
    fi
    for n in "${pk[@]}"; do
      if has "$n" && [[ "$flags" == *" --needed "* ]]; then echo "warning: $n is up to date -- skipping"
      else install_one "$n" 1; fi
    done ;;
  -R|-Rs)
    for n in "${pk[@]}"; do has "$n" || { echo "error: target not found: $n" >&2; exit 1; }; done
    for n in "${pk[@]}"; do del_pkg "$n"; done
    # refuse to break dependencies, like pacman
    while read -r n v r; do
      for d in $(deps_of "$n"); do has "$d" || { echo "error: removing would break $n -> $d" >&2; exit 1; }; done
    done < <(cat "$db")
    if [ "$op" = "-Rs" ]; then
      for n in "${pk[@]}"; do for d in $(deps_of "$n"); do
        if has "$d" && [ "$(reason "$d")" = 0 ] && ! awk '{print $1}' "$db" | while read -r o; do deps_of "$o"; done | grep -qx "$d"; then del_pkg "$d"; fi
      done; done
    fi ;;
  -U)
    for f in "${pk[@]}"; do
      [ -f "$f" ] || { echo "error: '$f': cannot open package file" >&2; exit 1; }
      b="$(basename "$f")"; b="${b%-*.pkg.tar.*}"          # strip -arch.pkg.tar.ext
      rel="${b##*-}"; b="${b%-*}"; ver="${b##*-}-$rel"; n="${b%-*}"
      if has "$n"; then set_pkg "$n" "$ver" "$(reason "$n")"; else set_pkg "$n" "$ver" 1; fi
    done ;;
  -D)
    r=1; [[ "$flags" == *" --asdeps "* ]] && r=0
    for n in "${pk[@]}"; do set_pkg "$n" "$(awk -v n="$n" '$1==n{print $2}' "$db")" "$r"; done ;;
  *) echo "fake pacman: unsupported operation $op" >&2; exit 2 ;;
esac
