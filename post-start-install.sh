#!/bin/bash
# The main work devcontainer runs this at the end of every environment start, after everything
# it sets up itself (the EFS mount included). Other repositories don't run it; there, the
# SSH-login block in rex.zsh starts Rex instead.
#
# Having this file replaces that devcontainer's default hook, so that runs first: it links ~/.claude,
# the gh config and Codex's login onto EFS, which is how sign-ins survive a new environment.
# It is run in place, not copied here, so it stays current with the repository.
here="$(dirname "$(readlink -f "$0")")"

if [ -n "${EFS_MOUNT_POINT:-}" ] && [ "$EFS_MOUNT_POINT" != "/home/vscode" ]; then
  for hook in /workspaces/*/.devcontainer/bin/default-post-install-efs-hook; do
    if [ -x "$hook" ]; then
      "$hook" || echo "WARNING: $hook failed; sign-ins may not be on EFS" >&2
      break
    fi
  done
fi

# A failure here (no network, a held dpkg lock) is reported, not fatal: the next SSH login
# tries again.
"$here/rex-setup.sh" || echo "WARNING: rex-setup.sh failed; run ~/dotfiles/rex-setup.sh to retry" >&2
