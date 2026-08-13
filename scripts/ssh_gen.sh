#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/gpg_batch.sh
source "$SCRIPT_DIR/lib/gpg_batch.sh"

load_repo_env
require_env_vars GIT_EMAIL

target_user=""
target_home="$HOME"

if [[ "$(id -u)" -eq 0 ]]; then
  target_user="${SUDO_USER:-${USER:-}}"
  if [[ -n "$target_user" ]]; then
    target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
  fi

  if [[ -z "$target_home" ]]; then
    target_home="$HOME"
  fi
fi

ssh_dir="$target_home/.ssh"
github_key_path="$ssh_dir/id_github"

ensure_ssh_agent_shell_init() {
  local bashrc
  bashrc="$target_home/.bashrc"

  touch "$bashrc"

  if ! grep -Fq 'eval "$(ssh-agent -s)" >/dev/null' "$bashrc"; then
    {
      echo ''
      echo '# Start ssh-agent automatically for interactive shells.'
      echo 'if [[ $- == *i* && -z "${SSH_AUTH_SOCK:-}" ]]; then'
      echo '  eval "$(ssh-agent -s)" >/dev/null'
      echo 'fi'
    } >> "$bashrc"
    echo "Added ssh-agent startup to $bashrc"
  fi

  if [[ "$(id -u)" -eq 0 && -n "$target_user" ]]; then
    chown "$target_user:$target_user" "$bashrc" 2>/dev/null || true
  fi
}

ensure_ssh_agent_shell_init

echo "Managing SSH keys for multiple providers"
mkdir -p "$ssh_dir"
# If running as root, set ownership before changing permissions
if [[ "$(id -u)" -eq 0 && -n "$target_user" ]]; then
  chown "$target_user:$target_user" "$ssh_dir"
fi

chmod 700 "$ssh_dir"

# Resolve SSH key TTL: prefer SSH_KEY_EXPIRATION, fall back to GPG_EXPIRATION.
ssh_ttl_raw="${SSH_KEY_EXPIRATION:-${GPG_EXPIRATION:-1y}}"
ssh_ttl_seconds="$(parse_expiry_to_seconds "$ssh_ttl_raw")"

THIRTY_DAYS=$(( 30 * 86400 ))
NOW="$(date +%s)"

# generate github key
if [[ ! -f "$github_key_path" ]]; then
  echo "No SSH key found; generating ED25519 SSH key for GitHub..."
  ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$github_key_path" -N ""
  echo "SSH key generated."
  # Signal to the orchestrator that keys changed.
  [[ -n "${KEYS_CHANGED_FLAG:-}" ]] && touch "$KEYS_CHANGED_FLAG" || true
else
  key_mtime="$(stat -c %Y "$github_key_path")"
  key_expiry_epoch=$(( key_mtime + ssh_ttl_seconds ))
  seconds_until_expiry=$(( key_expiry_epoch - NOW ))

  if [[ $seconds_until_expiry -le $THIRTY_DAYS ]]; then
    days_left=$(( seconds_until_expiry / 86400 ))
    echo "SSH key expires in ${days_left} day(s) (based on creation time + TTL); regenerating."
    # Back up existing keys before overwriting.
    cp -f "$github_key_path"     "${github_key_path}.bak"
    cp -f "${github_key_path}.pub" "${github_key_path}.pub.bak"
    rm -f "$github_key_path" "${github_key_path}.pub"
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$github_key_path" -N ""
    echo "SSH key regenerated (previous key backed up as id_github.bak)."
    # Signal to the orchestrator that keys changed.
    [[ -n "${KEYS_CHANGED_FLAG:-}" ]] && touch "$KEYS_CHANGED_FLAG" || true
  else
    days_left=$(( seconds_until_expiry / 86400 ))
    echo "SSH key is valid for ${days_left} more day(s); skipping regeneration."
  fi
fi

# Follow github key generation method for additional keys here

# Optional: create a reusable GPG batch template from .env values.
if [[ "${GENERATE_GPG_BATCH_TEMPLATE:-false}" == "true" ]]; then
  gpg_template_file="$ssh_dir/gpg_batch"
  create_gpg_batch_file "$gpg_template_file"
  chmod 600 "$gpg_template_file"
  echo "Created GPG batch template at $gpg_template_file"
fi

# create SSH config file to route keys correctly
cat > "$ssh_dir/config" <<EOF
Host linux_gh
  HostName github.com
  User git
  IdentityFile $github_key_path
  IdentitiesOnly yes
EOF

chmod 600 "$ssh_dir/config"

if [[ "$(id -u)" -eq 0 && -n "$target_user" ]]; then
  chown "$target_user:$target_user" "$ssh_dir" "$github_key_path" "${github_key_path}.pub" "$ssh_dir/config" 2>/dev/null || true
fi
echo "-------------------------------------------------------"
