# Shared files

| File | What it is |
|---|---|
| [mcp-firewall.service](mcp-firewall.service) | systemd unit with an iptables rule in `DOCKER-USER`: only Caddy may reach the MCP ports |
| [Caddyfile.snippets](Caddyfile.snippets) | `(int_only)` snippet, internal Bearer sites, public OAuth sites with the Anthropic IP allow list |
| [claude-mcp-add.md](claude-mcp-add.md) | `claude mcp add` commands for Claude Code |

## mcp-firewall.service

The file is the version from the calendar guide (ports 3000 and 8080, Caddy at `192.168.1.10`, interface `eth0`). Copy it to `/etc/systemd/system/mcp-firewall.service` and adapt three things:

1. **Caddy IP**: replace `192.168.1.10` everywhere (also in `Description`).
2. **Ports**: the list after `--dports`. Calendar with auth proxy: `3000,8080`. Calendar for Claude Code only, UniFi, Paperless, WHOOP: `3000`.
3. **Interface**: check with `ip -br link`. In an LXC it is usually `eth0`, in a VM often `ens18`. Replace `eth0` everywhere if yours differs. With the wrong name the rule does not apply, or Caddy gets a 502.

Why `DOCKER-USER`: ports published by Docker bypass the normal INPUT rules, and Docker leaves this chain for your own rules.
Why `-i eth0`: the rule then only hits packets from outside. Without it, it also blocks traffic between containers, and the auth proxy can no longer reach the calendar server.
`ExecStart` deletes an old copy of the rule first, so it never ends up in the chain twice.

The rule is IPv4 only. That is why the compose files publish ports as `0.0.0.0:3000:3000`: without the `0.0.0.0:` Docker also publishes them over IPv6, where this rule does not apply.

Order: enable the firewall first, then start the containers.

```bash
systemctl daemon-reload
systemctl enable --now mcp-firewall.service
iptables -L DOCKER-USER -n -v --line-numbers   # the DROP rule must show up exactly once
docker compose up -d
```

The Proxmox MCP runs without Docker and uses nftables instead, see [../proxmox/nftables.conf](../proxmox/nftables.conf).
