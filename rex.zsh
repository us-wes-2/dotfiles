# Rex on Ona: shell helpers. install.sh adds one line to ~/.zshrc that sources this file, so
# the environment's own ~/.zshrc is left as it is. Changes here apply to new shells after a
# `git pull` in ~/dotfiles.

# rex: rex-setup.sh is the one place that knows how the server starts (with
# --tailscale and this environment's node name). A bare "rex server start" typed
# by hand goes through it, so it can't come up as Tailscale's default "rex".
# Anything else passes straight through.
rex() {
  if [[ $# -eq 2 && "$1" == server && "$2" == start && -x "$HOME/dotfiles/rex-setup.sh" ]]; then
    "$HOME/dotfiles/rex-setup.sh"
  else
    command rex "$@"
  fi
}

alias rex-status="rex server status"
alias rex-retry-cert="rex server tailscale off && rex server tailscale on"

# On an interactive SSH login: start the server if none is running. Otherwise print the
# tailnet URL so it can be copied, or the Tailscale sign-in link when the server still needs
# one. The post-start hook also starts the server, but it runs after the rest of the
# environment's setup, which can take minutes after a power-on; logging in first starts it
# the same way, and the hook's later start is a no-op.
# --autostart=false keeps a status check from launching a server without --tailscale.
# Shells that Rex itself opens (TERM_PROGRAM=rex) skip this: the server is plainly up.
if [[ -o interactive && -n "$SSH_CONNECTION" && "$TERM_PROGRAM" != rex ]]; then
  if (( $+commands[rex] )) && rex_status=$(command rex server status --autostart=false --timeout 2s 2>/dev/null); then
    # The https line reads "pending" until the certificate is issued, so only an actual URL
    # counts.
    rex_url=$(print -r -- "$rex_status" | sed -n 's|^  https: \(https://.*\)|\1|p')
    rex_login_url=$(print -r -- "$rex_status" | sed -n 's/^  authenticate: //p')
    if [[ -n "$rex_login_url" ]]; then
      echo "rex: Tailscale sign-in needed: $rex_login_url"
    elif [[ -n "$rex_url" ]]; then
      echo "rex tailnet url:"
      echo "$rex_url"
    else
      echo "rex: server running, tailnet https not ready yet (check rex-status)"
    fi
  elif [[ -x "$HOME/dotfiles/rex-setup.sh" ]]; then
    echo "rex: no server running, starting one"
    "$HOME/dotfiles/rex-setup.sh" || echo "rex: setup failed; run ~/dotfiles/rex-setup.sh to retry"
  fi
  unset rex_status rex_url rex_login_url
fi

# Rex sessions: the Mac app creates sessions without a working directory, so their shells
# start in $HOME. Start in the workspace instead: the single repository under /workspaces.
# Splits and tabs that inherit a pane's directory are already elsewhere and are left alone.
if [[ "$TERM_PROGRAM" == rex && "$PWD" == "$HOME" ]]; then
  rex_repos=(/workspaces/*(N/))
  if (( ${#rex_repos} == 1 )); then
    cd "${rex_repos[1]}"
  fi
  unset rex_repos
fi
