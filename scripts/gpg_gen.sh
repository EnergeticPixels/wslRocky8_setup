#!/usr/bin/env bash
set -euo pipefail

# If invoked via sudo as root, re-run as the original user so keys are
# generated in the user's keyring instead of /root.
if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" && "${GPG_GEN_REEXEC_AS_USER:-0}" != "1" ]]; then
  export GPG_GEN_REEXEC_AS_USER=1
  exec sudo -u "$SUDO_USER" -H bash "$0" "$@"
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/gpg_batch.sh
source "$SCRIPT_DIR/lib/gpg_batch.sh"

load_repo_env
require_env_vars GIT_NAME GIT_EMAIL GPG_EXPIRATION

ensure_gpg_tty_shell_init() {
  local target_user target_home bashrc

  target_home="$HOME"

  if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    target_user="${SUDO_USER:-}"
    target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
  fi

  if [[ -z "$target_home" ]]; then
    target_home="$HOME"
  fi

  bashrc="$target_home/.bashrc"
  touch "$bashrc"

  if ! grep -Fq 'export GPG_TTY=$(tty)' "$bashrc"; then
    {
      echo ''
      echo '# Keep GPG pinentry working in interactive shells.'
      echo 'export GPG_TTY=$(tty)'
    } >> "$bashrc"
    echo "Added GPG_TTY export to $bashrc"
  fi

  if [[ "${EUID:-$(id -u)}" -eq 0 && -n "$target_user" ]]; then
    chown "$target_user:$target_user" "$bashrc" 2>/dev/null || true
  fi
}

ensure_gpg_tty_shell_init

# Set GPG_TTY in current session for signing to work in WSL/interactive environments
export GPG_TTY=$(tty)
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true

uid="$GIT_NAME <$GIT_EMAIL>"

prompt_for_gpg_passphrase() {
  local pass1 pass2

  while true; do
    read -r -s -p "Enter GPG passphrase: " pass1
    echo ""
    read -r -s -p "Confirm GPG passphrase: " pass2
    echo ""

    if [[ -z "$pass1" ]]; then
      echo "GPG passphrase cannot be empty." >&2
      continue
    fi

    if [[ "$pass1" != "$pass2" ]]; then
      echo "Passphrases do not match. Try again." >&2
      continue
    fi

    GPG_PASSPHRASE="$pass1"
    break
  done
}

gpg_with_passphrase() {
  printf '%s\n' "$GPG_PASSPHRASE" | gpg --batch --pinentry-mode loopback --passphrase-fd 0 "$@"
}

# ---------------------------------------------------------------------------
# Check whether a GPG key for this identity already exists in the keyring.
# ---------------------------------------------------------------------------
resolve_gpg_key_info() {
  local _email="$1"

  GPG_KEY_ID="$({
    gpg --batch --with-colons --list-secret-keys 2>/dev/null || true
  } | awk -F: -v email="$_email" '
    $1 == "sec" { current_keyid = $5; current_expiry = $7; next }
    $1 == "uid" && current_keyid != "" {
      if (index($10, email) > 0) { print current_keyid ":" current_expiry; exit }
    }
  ')"

  GPG_FPR="$({
    gpg --batch --with-colons --list-secret-keys 2>/dev/null || true
  } | awk -F: -v email="$_email" '
    $1 == "sec" { current_keyid = $5; next }
    $1 == "fpr" && current_keyid != "" { fpr_by_keyid[current_keyid] = $10; next }
    $1 == "uid" && current_keyid != "" {
      if (index($10, email) > 0) { print fpr_by_keyid[current_keyid]; exit }
    }
  ')"
}

resolve_gpg_key_info "$GIT_EMAIL"

do_generate_gpg_key() {
  prompt_for_gpg_passphrase

  # Generate a signing-capable Ed25519 primary key.
  gpg_with_passphrase --quick-generate-key "$uid" ed25519 sign "$GPG_EXPIRATION"

  # Re-resolve key info after generation.
  resolve_gpg_key_info "$GIT_EMAIL"

  # Fall back to first available key if email match failed.
  if [[ -z "$GPG_KEY_ID" ]]; then
    GPG_KEY_ID="$({
      gpg --batch --with-colons --list-secret-keys 2>/dev/null || true
    } | awk -F: '$1 == "sec" { print $5; exit }')"
  fi

  if [[ -z "$GPG_FPR" ]]; then
    GPG_FPR="$({
      gpg --batch --with-colons --list-secret-keys 2>/dev/null || true
    } | awk -F: '$1 == "fpr" { print $10; exit }')"
  fi

  if [[ -z "$GPG_FPR" ]]; then
    echo "Unable to locate the generated GPG key fingerprint. Verify .env values and gpg installation." >&2
    exit 1
  fi

  # Ensure there is an encryption subkey for provider workflows.
  local has_encrypt_subkey
  has_encrypt_subkey="$({
    gpg --batch --with-colons --list-secret-keys "$GPG_FPR" 2>/dev/null || true
  } | awk -F: '$1 == "ssb" && index($12, "e") > 0 { found=1 } END { print found+0 }')"

  if [[ "$has_encrypt_subkey" -eq 0 ]]; then
    gpg_with_passphrase --quick-add-key "$GPG_FPR" cv25519 encrypt "$GPG_EXPIRATION"
  fi

  unset GPG_PASSPHRASE
  echo "GPG key generated."
  # Signal to the orchestrator that keys changed.
  [[ -n "${KEYS_CHANGED_FLAG:-}" ]] && touch "$KEYS_CHANGED_FLAG" || true
}

# ---------------------------------------------------------------------------
# Decide: generate, skip, or regenerate based on expiry.
# ---------------------------------------------------------------------------
THIRTY_DAYS=$(( 30 * 86400 ))
NOW="$(date +%s)"

if [[ -z "$GPG_KEY_ID" ]]; then
  # No key exists — generate fresh.
  echo "No GPG key found for $GIT_EMAIL; generating."
  do_generate_gpg_key
else
  # Key exists — parse the existing expiry.
  existing_expiry="${GPG_KEY_ID#*:}"
  GPG_KEY_ID="${GPG_KEY_ID%%:*}"

  if [[ -z "$existing_expiry" || "$existing_expiry" -eq 0 ]]; then
    echo "GPG key for $GIT_EMAIL has no expiry; skipping regeneration."
  elif [[ $(( existing_expiry - NOW )) -le $THIRTY_DAYS ]]; then
    days_left=$(( (existing_expiry - NOW) / 86400 ))
    echo "GPG key for $GIT_EMAIL expires in ${days_left} day(s); regenerating."
    # Remove old key to prevent duplicate UID entries.
    gpg --batch --yes --delete-secret-and-public-key "$GPG_FPR" 2>/dev/null || true
    GPG_KEY_ID=""
    GPG_FPR=""
    do_generate_gpg_key
  else
    days_left=$(( (existing_expiry - NOW) / 86400 ))
    echo "GPG key for $GIT_EMAIL is valid for ${days_left} more day(s); skipping regeneration."
  fi
fi