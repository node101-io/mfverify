# mfverify

Fetches a Monad Foundation node-ops announcement from
[mf-nodeops-comms](https://github.com/monad-crypto/mf-nodeops-comms) and verifies its GPG signatures. It replaces
the manual steps (import the keys, compare fingerprints, run `gpg --verify`, count signers) with one command.

```console
$ mfverify        # the latest announcement
Finding the latest announcement... #6
Downloading announcement #6... done
Downloading the list of authorized keys from the docs... 5 active
Downloading their key files from GitHub... done
Verifying the signatures with sqv:
  signer_1    ✓ valid signature
  signer_2    ✓ valid signature
  signer_3    – did not sign
  signer_4    – did not sign
  signer_6    – did not sign
Checking the header... "MF Announcement #6"

✓ Verified #6 (signer_1, signer_2)

MF Announcement #6
...
$ mfverify 6      # announcement #6
```

Progress goes to stderr and the verified announcement to stdout. `-q` hides the progress, `-v` adds each
key's fingerprint to it.

The text is printed only if all checks pass. Otherwise `mfverify` prints why and exits with status 1. A network
error is reported as such ("could not be verified ... try again"), not as a failed verification.

## Install

```sh
sudo apt install sqv curl        # macOS: brew install sequoia-sqv
curl -fsSLO https://raw.githubusercontent.com/node101-io/mfverify/main/mfverify
less mfverify                    # it is short: read it
chmod +x mfverify
```

## What it checks

- At least two valid signatures from **distinct** authorized keys. A key is authorized when both of the
  Foundation's sources agree on it: its file is in `keys/` of mf-nodeops-comms on GitHub, and its primary-key
  fingerprint is listed as `active` in https://docs.monad.xyz/node-ops/gpg-keys.json. This is the Foundation's own
  verification procedure, done on every run. The signatures are checked by
  [sqv](https://gitlab.com/sequoia-pgp/sequoia-sqv), which also rejects expired or revoked signatures, keys and
  certificates.
- The first line of the text is `MF Announcement #N` (or `Announcement #N`, as in #3) for the requested `N`. This
  stops a validly signed old announcement from being passed off as another one.
- Each key is checked on its own, so a key file that cannot be read or downloaded only keeps that key from
  counting.
- It notes when the announcement is not the latest one. The latest is found by probing `announcements/mf-N`; a
  network error while probing stops `mfverify` instead of being taken for "no newer announcement".

Control characters other than tab and newline are removed before the text is printed.

## What you trust

GitHub and docs.monad.xyz not being compromised **together**, `sqv`, and this script. A key added, replaced or
re-activated in only one of the two places does not count, because a new key must never be trusted only because it
appears in the download location. A changed announcement fails verification.

Both sources are run by the Foundation, so they are not fully independent. Key rotations and revocations take
effect without updating this script.

Whoever controls your network can still hide announcements newer than the one you see. Compare the number with
the one in the Foundation's message.

docs.monad.xyz sometimes answers bursts of requests with a bot challenge (HTTP 403) for a few minutes. `mfverify`
then says so and accepts nothing; try again later.

## Tests

```sh
./test.sh    # needs network access, sqv and gpg
```

It verifies every published announcement and checks the progress output, `-q`, a non-signer's unreadable key file
(still accepted) and a network error while finding the latest (rejected). Then it checks that these are rejected:
tampered text, a valid announcement served under another number, a single signature, the same signature twice, a
missing key file, signers that are not active in the docs, and a new key added only to `keys/`, only to the docs,
in place of signer_1's file, or under a docs name that points outside `keys/`. A new key added to both places is
accepted.
`MFVERIFY_BASE` and `MFVERIFY_KEYS_JSON` let the tests serve local files; the signatures are checked the same way.

Tested on macOS (sqv 1.5.0, with bash and dash as `sh`). Earlier versions were also tested on Ubuntu 24.04 (sqv 1.1.0).

## TODO

- Ask the Monad Foundation to exempt `/node-ops/gpg-keys.json` from the docs site's Vercel bot challenge (see above).
