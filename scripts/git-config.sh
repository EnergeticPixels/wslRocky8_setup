#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/gpg_batch.sh
source "$SCRIPT_DIR/lib/gpg_batch.sh"

load_repo_env
require_env_vars GIT_NAME GIT_EMAIL

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

gitconfig_path="$target_home/.gitconfig"
mkdir -p "$target_home"
touch "$gitconfig_path"

if [[ "$(id -u)" -eq 0 && -n "$target_user" ]]; then
	chown "$target_user:$target_user" "$gitconfig_path" 2>/dev/null || true
fi

# Resolve signing key if it was not exported by previous scripts.
if [[ -z "${GPG_KEY_ID:-}" ]]; then
	GPG_KEY_ID="$({
		gpg --batch --with-colons --list-secret-keys 2>/dev/null || true
	} | awk -F: -v email="$GIT_EMAIL" '
		$1 == "sec" {
			current_keyid = $5
			next
		}
		$1 == "uid" && current_keyid != "" {
			if (index($10, email) > 0) {
				print current_keyid
				exit
			}
		}
	')"
fi

if [[ -z "${GPG_KEY_ID:-}" ]]; then
	GPG_KEY_ID="$({
		gpg --batch --with-colons --list-secret-keys 2>/dev/null || true
	} | awk -F: '$1 == "sec" { print $5; exit }')"

	if [[ -n "$GPG_KEY_ID" ]]; then
		echo "No secret key matched GIT_EMAIL=$GIT_EMAIL; using first available secret key ID: $GPG_KEY_ID" >&2
	fi
fi

if [[ -z "${GPG_KEY_ID:-}" ]]; then
	echo "Unable to find any GPG secret key. Run scripts/gpg_gen.sh first." >&2
	exit 1
fi

git_user_name="$GIT_NAME"
git_user_email="$GIT_EMAIL"

# If the selected key's UID email differs, prefer key UID values for git identity.
gpg_uid="$({
	gpg --batch --with-colons --list-secret-keys "$GPG_KEY_ID" 2>/dev/null || true
} | awk -F: '$1 == "uid" { print $10; exit }')"

if [[ -n "$gpg_uid" ]]; then
	gpg_uid_name="${gpg_uid%% <*}"
	gpg_uid_email="$({
		printf '%s\n' "$gpg_uid"
	} | sed -n 's/.*<\([^>]*\)>.*/\1/p')"

	if [[ -n "$gpg_uid_email" && "$gpg_uid_email" != "$GIT_EMAIL" ]]; then
		echo "GIT_EMAIL=$GIT_EMAIL does not match selected key UID email=$gpg_uid_email; syncing git identity to key UID." >&2
		git_user_email="$gpg_uid_email"
		if [[ -n "$gpg_uid_name" ]]; then
			git_user_name="$gpg_uid_name"
		fi
	fi
fi

git config --file "$gitconfig_path" user.name "$git_user_name"
git config --file "$gitconfig_path" user.email "$git_user_email"

git config --file "$gitconfig_path" user.signingkey "$GPG_KEY_ID"
git config --file "$gitconfig_path" commit.gpgsign true

git config --file "$gitconfig_path" core.filemode false

git_alias_br_default='branch --format="%(HEAD) %(color:yellow)%(refname:short)%(color:reset) - %(contents:subject) %(color:green)(%(committerdate:relative)) [%(authorname)]" --sort=-committerdate'
git_alias_lg_default='!git log --pretty=format:"%C(magenta)%h%Creset %C(red)%d%Creset %s %C(dim green)(%cr) [%an]" --abbrev-commit -30'

git_alias_br="${GIT_ALIAS_BR:-$git_alias_br_default}"
git_alias_lg="${GIT_ALIAS_LG:-$git_alias_lg_default}"

git config --file "$gitconfig_path" alias.br "$git_alias_br"
git config --file "$gitconfig_path" alias.lg "$git_alias_lg"

echo "Updated git config at $gitconfig_path"
