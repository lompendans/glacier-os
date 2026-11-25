#!/usr/bin/env bash
# End-to-end test: drives the real floe binary against fake-pacman.sh.
# usage: tests/e2e.sh path/to/floe
set -euo pipefail
FLOE="$(realpath "${1:?usage: e2e.sh path/to/floe}")"
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FLOE_ROOT="$T/root" FLOE_CACHE="$T/cache" FLOE_NO_SUDO=1 NO_COLOR=1
export FAKE_DB="$T/db" FAKE_REPO="$T/repo" FAKE_DEPS="$T/deps" FLOE_PACMAN="$HERE/fake-pacman.sh"
chmod +x "$FLOE_PACMAN"

cat > "$FAKE_REPO" <<'EOF'
core bash 5.2-1 The GNU Bourne Again shell
extra firefox 133.0-1 Fast private web browser
extra nss 3.106-1 Network Security Services
extra krita 5.2.6-1 Painting program
extra qt6-base 6.8.0-1 Qt toolkit
EOF
printf 'firefox nss\nkrita qt6-base\n' > "$FAKE_DEPS"
echo "bash 5.2-1 1" > "$FAKE_DB"

pass=0
ok()   { pass=$((pass+1)); echo "  ok  $1"; }
fail() { echo "FAIL  $1"; echo "--- db:"; cat "$FAKE_DB"; echo "--- history:"; "$FLOE" history || true; exit 1; }
db_is() { diff <(sort "$FAKE_DB") <(printf '%s\n' "$@" | sort) >/dev/null; }
gen_is() { [ "$(ls "$FLOE_ROOT/var/lib/floe/generations" | wc -l)" -eq "$1" ]; }

"$FLOE" install -y firefox >/dev/null
db_is "bash 5.2-1 1" "firefox 133.0-1 1" "nss 3.106-1 0" && gen_is 2 || fail "install creates initial + install generations"
ok "install"

"$FLOE" install -y firefox >/dev/null
gen_is 2 || fail "reinstalling with --needed must not create a generation"
ok "no-op install creates no generation"

"$FLOE" install -y krita >/dev/null
"$FLOE" remove -y firefox >/dev/null
db_is "bash 5.2-1 1" "krita 5.2.6-1 1" "qt6-base 6.8.0-1 0" && gen_is 4 || fail "remove drops orphaned deps"
ok "remove (with orphaned dependency)"

"$FLOE" rollback -y >/dev/null
db_is "bash 5.2-1 1" "firefox 133.0-1 1" "nss 3.106-1 0" "krita 5.2.6-1 1" "qt6-base 6.8.0-1 0" && gen_is 5 || fail "rollback restores firefox and marks nss as a dependency"
ok "rollback restores removed packages with correct install reasons"

sed -i 's/^extra krita 5.2.6-1/extra krita 5.3.0-1/' "$FAKE_REPO"
"$FLOE" upgrade -y >/dev/null
grep -q "^krita 5.3.0-1 1$" "$FAKE_DB" && gen_is 6 || fail "upgrade"
ok "upgrade"

"$FLOE" rollback -y >/dev/null
grep -q "^krita 5.2.6-1 1$" "$FAKE_DB" && gen_is 7 || fail "rollback downgrades from cache"
ok "rollback downgrades from the cache"

"$FLOE" rollback 1 -y >/dev/null
db_is "bash 5.2-1 1" && gen_is 8 || fail "rollback to generation 1"
ok "rollback to an explicit generation"

"$FLOE_PACMAN" -S krita >/dev/null   # change made with pacman directly, bypassing floe
"$FLOE" install -y firefox >/dev/null
"$FLOE" history | grep -q "external changes" || fail "external pacman changes are recorded"
gen_is 10 || fail "external change + install = 2 new generations"
ok "changes made with pacman directly are recorded"

rm "$FLOE_CACHE"/firefox-133.0-1-x86_64.pkg.tar.zst
"$FLOE" remove -y firefox >/dev/null
before="$(cat "$FAKE_DB")"; gens_before="$(ls "$FLOE_ROOT/var/lib/floe/generations" | wc -l)"
if "$FLOE" rollback -y >"$T/out" 2>&1; then fail "rollback must fail when a cached package is missing"; fi
grep -q "no longer in" "$T/out" && grep -q "Nothing was changed" "$T/out" || fail "missing-cache error message"
[ "$(cat "$FAKE_DB")" = "$before" ] || fail "system must be untouched after a refused rollback"
gen_is "$gens_before" || fail "a refused rollback must not record a generation"
ok "refuses rollback when the cache was cleaned, changes nothing"

"$FLOE" rollback 999 -y >/dev/null 2>&1 && fail "unknown generation must error"
ok "unknown generation errors"

out="$("$FLOE" search fire --json)"
echo "$out" | grep -q '"name":"firefox"' || fail "search --json"
"$FLOE" history --json | grep -q '"n":1' || fail "history --json"
"$FLOE" list --json | grep -q '"name":"bash"' || fail "list --json"
ok "json output"

"$FLOE" bogus >/dev/null 2>&1 && fail "unknown command must exit non-zero"
ok "unknown command exits non-zero"

touch "$FAKE_DB.nosync"
if "$FLOE" search fire >"$T/out" 2>&1; then fail "search without package lists must fail"; fi
grep -q "floe refresh" "$T/out" || fail "missing package lists should point to 'floe refresh'"
"$FLOE" refresh >/dev/null || fail "refresh"
"$FLOE" search fire --json | grep -q '"name":"firefox"' || fail "search works after refresh"
ok "missing package lists: clear hint, fixed by floe refresh"

sed -i 's/^core bash 5.2-1/core bash 5.3-1/' "$FAKE_REPO"
"$FLOE" install -y krita >/dev/null 2>&1 || true
grep -q "^bash 5.3-1 1$" "$FAKE_DB" || fail "install must upgrade the system first (no partial upgrades)"
ok "install upgrades the system first (no partial upgrades)"

echo "all $pass end-to-end checks passed"
