# Disaster Recovery / New Machine Restore

The whole point of this repo: a new machine (or a rebuilt one) comes back
with **one password** — the Bitwarden master password (+2FA). Everything
else is derived.

## What you need

- Bitwarden master password (+ 2FA device)
- The bootstrap one-liner below
- Nothing else: SSH keys, age key, GitHub token, secrets files all come
  from the vault or the encrypted repo.

## Bootstrap

```bash
curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/install/setup.sh | bash
```

Flow after the clone:

1. `bw` CLI installed from GitHub releases.
2. Interactive `bw login` + unlock (the one password you type).
3. Three questions: the URL of your fork, the private encrypted
   repository, the Bitwarden email. Environment variables `REMOTE_URL`,
   `PRIVATE_URL` and `BW_EMAIL` skip them.
4. `GITHUB_API_KEY` from the vault authorizes the private repo
   (`doryashar/encrypted`) — the SSH key chicken-and-egg is solved by
   this token.
5. `AGE_SECRET` from the vault decrypts `var/private_encrypted/*` into
   `var/private/` (0600, world-unreadable).
6. First successful decrypt also caches the age identity to
   `~/.config/age/secret` (0600) — after this, **syncs never need the
   vault again**.
7. `sync_dotfiles` symlinks `var/private/ssh -> ~/.ssh`, `var/private ->
   ~/private`, `var/private/config/* -> ~/.config/*`.
8. The Go SDK and the tools that are not in git are downloaded
   and verified against `config/binaries.tsv`.

## Verify

```bash
ssh -T git@github.com                 # auth via restored key
ls ~/private/secrets                  # decrypted tree present
bw lock                               # optional: you don't need it open anymore
zsh -c 'source ~/private/env_work'    # work env restored
```

## Ongoing sync after restore

The secrets sync is a manual step: run `envsync`. It asks before
pulling, pushing or merging, so it is not scheduled.
`secrets-health.timer` sends a Telegram message when the last backup is
older than 48 hours. The vault is only needed again for key rotation
or a fresh machine.

## Key rotation

1. Generate a new age keypair (`age-keygen`), store the secret as the
   `AGE_SECRET` item in Bitwarden.
2. Delete `~/.config/age/secret` to force vault retrieval.
3. Update `var/private/age-recipients` with the new public key, run
   `sync_encrypted.sh` once to re-encrypt and push everything.
4. On other machines: delete their `~/.config/age/secret` and re-sync.

## Where things live (post-2026-11 reorg)

| Path | Content |
|------|---------|
| `var/private/` | decrypted secrets tree (gitignored, 0600) |
| `var/private_encrypted/` | clone of the encrypted GitHub repo (`.age` files) |
| `var/local_hashes` | content-only change-detection hashes |
| `~/.config/age/secret` | cached age identity for unattended sync |
| `config/repo.conf` | personal config (gitignored; template: `repo.conf.example`) |
| `config/dotfiles.conf` | symlink mappings incl. the private tree |
| bin/, go-1.27.0/ | not in git; setup.sh downloads and verifies them from config/binaries.tsv |
| config/binaries.tsv | pinned URLs and sha256 of those downloads |
