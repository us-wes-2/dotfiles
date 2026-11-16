#!/bin/bash
# Install Rex on this Ona environment and serve it on the tailnet, so Rex for Mac can reach the
# environment as a host of its own and sessions keep running here when the laptop is away.
#
# Based on Daniel Sauerbrun's "Rex on Ona via dotfiles" (https://github.com/dsauerbrun/dotfiles).
#
# This is the one place that decides how the server starts. It runs from
# post-start-install.sh on every environment start, from rex.zsh on the first SSH
# login that finds no server, and in place of a bare "rex server start" typed
# by hand (see the rex function in rex.zsh). Every path gets the same flags.
# Safe to run any number of times.
set -euo pipefail

# The Ona CLI is `ona` on newer images and `gitpod` on older ones.
ona_cli() {
  if command -v ona >/dev/null; then
    ona "$@"
  else
    gitpod "$@"
  fi
}

# Node names are shared across every engineer's environments on the tailnet, so
# build <first initial><last name>-<ona environment name>-rex. The owner comes
# from first.last@ in the Ona owner email, falling back to the git author name.
default_hostname() {
  local owner env_name
  owner="${ONA_INSTANCE_OWNER_EMAIL:-}"
  owner="${owner%%@*}"
  if [ -z "$owner" ]; then
    owner="$(git config user.name 2>/dev/null | tr ' ' '.')"
  fi
  case "$owner" in
    *.*) owner="${owner:0:1}${owner##*.}" ;;
  esac
  env_name="$(ona_cli environment get --field name 2>/dev/null || true)"
  # DNS labels allow only lowercase letters, digits and hyphens, up to 63 chars.
  printf '%s' "${owner:+$owner-}${env_name:+$env_name-}rex" |
    tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | cut -c1-63
}

hostname="${REX_TAILSCALE_HOSTNAME:-$(default_hostname)}"

if ! command -v rex >/dev/null; then
  # Other setup can still hold the dpkg lock, which fails the installer outright.
  for attempt in 1 2 3; do
    curl -fsSL https://pkgs.superlogical.com/rex/install.sh | sh && break
    if [ "$attempt" -eq 3 ]; then
      echo "ERROR: rex install failed" >&2
      exit 1
    fi
    sleep 20
  done
fi

# Teach the agents to use Rex: a skill for each, plus a session-start hook for
# Claude Code and Codex. The agents are named so none is skipped for not being
# detected yet. Setup reports what is already current as unchanged.
rex skill setup --agent claude --agent codex --agent opencode --agent pi

# Ona containers have no systemd, so run a detached user server. Start is a
# no-op when a server is already running, and its flags only apply to a server
# it launches itself.
rex server start --tailscale --tailscale-hostname "$hostname"

# A server that something else launched first (a bare "rex server start", or a
# rex command's autostart) came up with Tailscale's default node name, "rex",
# which the tailnet then suffixes to rex-2 and so on. Fix that in place rather
# than restarting, which would end every session. Tailscale may itself add a
# numeric suffix to our name when it collides, so accept hostname-N as well.
read -r ts_state ts_node < <(rex server status --autostart=false --json | python3 -I -c '
import json, sys
ts = json.load(sys.stdin).get("tailscale") or {}
print(ts.get("state") or "disabled", (ts.get("dns_name") or "").split(".")[0])')

if [ "$ts_state" = "disabled" ]; then
  echo "rex: Tailscale is off on the running server, turning it on as $hostname"
  rex server tailscale on --hostname "$hostname"
elif [ -n "${ts_node:-}" ] && [ "$ts_node" != "$hostname" ]; then
  case "$ts_node" in
    "$hostname"-[0-9]*) ;;
    *)
      echo "rex: Tailscale node is $ts_node, renaming to $hostname"
      rex server tailscale rename "$hostname"
      ;;
  esac
fi

# A new environment prints a Tailscale sign-in link here; later starts reuse the
# node state in ~/.local/state/rex.
rex server status | sed -n '/^tailscale/,/^log/p'

# End with the tailnet URL alone on a line, so it is easy to copy. The HTTPS
# certificate can take up to a minute after a fresh start, so wait for it
# briefly and say so if it is still pending.
ts_dns="-"
ts_https="pending"
for _ in $(seq 1 12); do
  read -r ts_dns ts_https < <(rex server status --autostart=false --json | python3 -I -c '
import json, sys
ts = json.load(sys.stdin).get("tailscale") or {}
print(ts.get("dns_name") or "-", (ts.get("https") or {}).get("state") or "pending")')
  [ "$ts_https" = "available" ] && break
  # Nothing to wait for until the node is signed in.
  [ "$ts_dns" = "-" ] && break
  sleep 5
done
if [ "$ts_dns" != "-" ]; then
  echo
  if [ "$ts_https" = "available" ]; then
    echo "rex tailnet url:"
  else
    echo "rex tailnet url (https still $ts_https, retry rex-status in a minute):"
  fi
  echo "https://$ts_dns"
fi
