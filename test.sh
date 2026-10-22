#!/bin/sh
# Tests for mfverify. Needs network access, sqv and gpg.
set -u
cd "$(dirname "$0")"

t=$(mktemp -d)
# Set before the trap, so that it only ever stops the tests' own gpg-agent.
export GNUPGHOME="$t/gnupg"; mkdir -m 700 "$GNUPGHOME"
trap 'gpgconf --kill gpg-agent 2>/dev/null; rm -rf "$t"' EXIT
fail=0
pass() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=1; }
# name, args...
accepts() { n=$1; shift; if ./mfverify "$@" >/dev/null 2>&1; then pass "$n"; else bad "$n"; fi; }
# Serves the repository files in $t/src and the docs' key list in $t/src/gpg-keys.json.
local_run() { MFVERIFY_BASE="file://$t/src" MFVERIFY_KEYS_JSON="file://$t/src/gpg-keys.json" ./mfverify "$1" >/dev/null 2>&1; }
# name, N
accepts_local() { if local_run "$2"; then pass "$1"; else bad "$1"; fi; }
rejects() { if local_run "$2"; then bad "$1"; else pass "$1"; fi; }

# docs.monad.xyz challenges bursts of requests, so all but one test use one copy of its key list.
raw=https://raw.githubusercontent.com/monad-crypto/mf-nodeops-comms/main
mkdir -p "$t/real/keys"
curl -fsS -o "$t/real/gpg-keys.json" https://docs.monad.xyz/node-ops/gpg-keys.json ||
  { echo "cannot download the key list from docs.monad.xyz; try again in a few minutes"; exit 1; }

# The latest announcement, end to end.
accepts "latest"

# Every published announcement.
n=0
while curl -fsI -o /dev/null "$raw/announcements/mf-$n/announcement.txt"; do
  if MFVERIFY_KEYS_JSON="file://$t/real/gpg-keys.json" ./mfverify $n >/dev/null 2>&1; then pass "#$n"; else bad "#$n"; fi
  n=$((n + 1))
done
[ $n -gt 6 ] || bad "found only $n announcements"

# Real files to tamper with.
for n in 5 6; do
  mkdir -p "$t/real/mf-$n"
  curl -fsS -o "$t/real/mf-$n/announcement.txt" "$raw/announcements/mf-$n/announcement.txt"
  curl -fsS -o "$t/real/mf-$n/announcement.sig" "$raw/announcements/mf-$n/announcement.sig"
done
for k in $(sed -n 's/^ *"\([A-Za-z0-9_-]*\)": *{.*/\1/p' "$t/real/gpg-keys.json" | tr - _); do
  curl -fsS -o "$t/real/keys/$k.pub.asc" "$raw/keys/$k.pub.asc" || bad "download keys/$k.pub.asc"
done
# mf-6's signature holds two packets, by signer_1 and signer_2; split them.
gpg --dearmor < "$t/real/mf-6/announcement.sig" > "$t/sig.bin"
len=$(gpg --list-packets "$t/sig.bin" 2>/dev/null | sed -n 's/^# off=0 .*hlen=\([0-9]*\) plen=\([0-9]*\).*/\1 \2/p')
len=$(( ${len% *} + ${len#* } ))
head -c $len "$t/sig.bin" > "$t/signer_1.sig"
tail -c +$(( len + 1 )) "$t/sig.bin" > "$t/signer_2.sig"

# Serves mf-6's real files as mf-N.
case_dir() {
  rm -rf "$t/src"; mkdir -p "$t/src/announcements/mf-$1"
  cp -R "$t/real/keys" "$t/real/gpg-keys.json" "$t/src/"
  cp "$t/real/mf-6/announcement.txt" "$t/real/mf-6/announcement.sig" "$t/src/announcements/mf-$1/"
}
d=$t/src/announcements/mf-6

case_dir 6; accepts_local "local copy of #6" 6

case_dir 6; sed 's/v0.16.5/v0.16.6/' "$t/real/mf-6/announcement.txt" > "$d/announcement.txt"
rejects "tampered text" 6

case_dir 6; cp "$t/real/mf-5/announcement.txt" "$t/real/mf-5/announcement.sig" "$d/"
rejects "valid #5 served as #6" 6

case_dir 7
rejects "valid #6 served as #7" 7

case_dir 6; cp "$t/signer_1.sig" "$d/announcement.sig"
rejects "one signature" 6

case_dir 6; cat "$t/signer_1.sig" "$t/signer_1.sig" > "$d/announcement.sig"
rejects "same signature twice" 6

case_dir 6; rm "$t/src/keys/signer_1.pub.asc"
rejects "signer's key file missing" 6

case_dir 6; sed 's/"active"/"revoked"/' "$t/real/gpg-keys.json" > "$t/src/gpg-keys.json"
rejects "signers not active in the docs" 6

# A new key, signing together with signer_2.
gpg -q --batch --passphrase '' --quick-gen-key new ed25519 sign never 2>/dev/null
gpg -q --batch --detach-sign -o "$t/new.sig" "$t/real/mf-6/announcement.txt"
fpr=$(gpg --with-colons --list-keys new 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
# key-file, json-name: adds the new key in either place, or both
new_key() {
  case_dir 6; cat "$t/signer_2.sig" "$t/new.sig" > "$d/announcement.sig"
  [ -z "$1" ] || gpg -q --export --armor new > "$t/src/$1"
  [ -z "$2" ] || sed "s|^{|{\"$2\": {\"fingerprint\": \"$fpr\", \"status\": \"active\"},|" \
    "$t/real/gpg-keys.json" > "$t/src/gpg-keys.json"
}

new_key keys/signer_7.pub.asc ""; rejects "new key only in keys/" 6
new_key "" signer-7; rejects "new key only in the docs" 6
new_key keys/signer_1.pub.asc ""; rejects "new key replacing signer_1's file" 6
new_key evil.pub.asc ../evil; rejects "docs name pointing outside keys/" 6
new_key keys/signer_7.pub.asc signer-7; accepts_local "new key in both places" 6

exit $fail
