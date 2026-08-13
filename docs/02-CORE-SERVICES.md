# Core Services

## SSH and GPG key management

Keys are managed automatically during each `provisioning.sh run`:

- No key found: a new key is generated.
- Key exists and healthy (more than 30 days before expiry): skipped; the log records days remaining.
- Key exists and near expiry (within 30 days): the key is replaced. Existing SSH key is backed up as `~/.ssh/id_github.bak`.

### Expiration variables

Set in `.env`:
- `GPG_EXPIRATION=1y`
- `SSH_KEY_EXPIRATION=1y`

### Public key display behavior

If any key was generated or rotated during the current run, both public keys are printed and the script pauses so you can copy them to GitHub.

Manual key output:

```bash
# GPG public key
gpg --armor --export "$GIT_EMAIL"

# SSH public key
cat ~/.ssh/id_github.pub
```

## Git identity and aliases

Configured by `scripts/git-config.sh`.

Set in `.env`:
- `GIT_NAME`
- `GIT_EMAIL`

Default aliases:
- `br = branch --format='%(HEAD) %(color:yellow)%(refname:short)%(color:reset) - %(contents:subject) %(color:green)(%(committerdate:relative)) [%(authorname)]' --sort=-committerdate`
- `lg = !git log --pretty=format:"%C(magenta)%h%Creset %C(red)%d%Creset %s %C(dim green)(%cr) [%an]" --abbrev-commit -30`

Optional overrides:
- `GIT_ALIAS_BR`
- `GIT_ALIAS_LG`

Run only Git setup:

```bash
sudo bash scripts/git-config.sh
```

## Vim default editor

Installed via `scripts/vim_install.sh`.

The script:
- Ensures `vim` is installed via apt
- Registers Vim via `update-alternatives`
- Writes `/etc/profile.d/editor.sh` with `EDITOR=vim` and `VISUAL=vim`

Run only Vim setup:

```bash
sudo bash scripts/vim_install.sh
```

## tmux optional configuration

If you want tmux configured automatically, set `TMUX_CONFIG_URL` in `.env` to a raw Gist URL for `.tmux.conf`.

Example:

```text
https://gist.github.com/<your-github-username>/<gist-hash>/raw/<your-gist-filename>
```

If no URL is provided, tmux setup is skipped and provisioning continues.

See also: [WSL Notes](07-WSL-NOTES.md)
