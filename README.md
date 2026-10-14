# homelab-mcp-stack

Deployment recipes for self-hosted MCP servers in a Proxmox homelab, so Claude (Claude Code and the claude.ai app) can work with your calendar, Proxmox, UniFi, Paperless-ngx and WHOOP.

These are **deployment recipes**. We did not fork any server. The repo holds only what we wrote around the upstream projects: compose files, a Dockerfile wrapper, systemd units, Caddy snippets and config templates. The servers themselves come from their upstream projects, linked below. Credit for the servers goes to their authors.

Guides with the reasoning behind each choice:

- Securing MCP connectors in a homelab: [EN](https://mapplebox.com/claude-homelab-mcp-secure/), [DE](https://mapplebox.de/claude-homelab-mcp-connectors-sicher/)
- iCloud calendar in Claude: [EN](https://mapplebox.com/icloud-calendar-claude-mcp/), [DE](https://mapplebox.de/icloud-kalender-claude-mcp/)
- Proxmox in Claude: [EN](https://mapplebox.com/proxmox-claude-mcp/), [DE](https://mapplebox.de/proxmox-claude-mcp/)

## The servers

| Folder | Upstream | Version we run | Port | Auth | Reachable | Guide |
|---|---|---|---|---|---|---|
| [calendar/](calendar/) | [caldav-mcp](https://github.com/dominik1001/caldav-mcp) via [supergateway](https://github.com/supercorp-ai/supergateway), [mcp-auth-proxy](https://github.com/sigbit/mcp-auth-proxy) | caldav-mcp 0.10.0, supergateway 4.1.0, mcp-auth-proxy v2.10.2 | 3000, 8080 | Bearer (internal), OAuth (public) | internal + public | [EN](https://mapplebox.com/icloud-calendar-claude-mcp/), [DE](https://mapplebox.de/icloud-kalender-claude-mcp/) |
| [proxmox/](proxmox/) | [ProxmoxMCP-Plus](https://github.com/RekklesNA/ProxmoxMCP-Plus) (PyPI `proxmox-mcp-plus`) | 0.5.27 | 8000 | Bearer (`MCP_API_KEY`, checked by the server) | internal | [EN](https://mapplebox.com/proxmox-claude-mcp/), [DE](https://mapplebox.de/proxmox-claude-mcp/) |
| [unifi/](unifi/) | [unifi-mcp](https://github.com/sirkirby/unifi-mcp) | `ghcr.io/sirkirby/unifi-network-mcp:0.20.3` | 3000 | Bearer | internal | |
| [paperless/](paperless/) | [paperless-ngx-mcp](https://github.com/cubinet-code/paperless-ngx-mcp) | `ghcr.io/cubinet-code/paperless-ngx-mcp:3.2.1` | 3000 | Bearer | internal | |
| [whoop/](whoop/) | [whoop-mcp-server](https://github.com/yuridivonis/whoop-mcp-server) | `ghcr.io/yuridivonis/whoop-mcp-server:1.5.1` | 3000 | built-in OAuth | public | |

"Version we run" means the version in our setup in October 2026. All image tags and package versions above existed on ghcr.io, npm and PyPI when we checked on 2026-10-15. Newer versions may change env variables or defaults, so read the upstream changelog before you bump a tag.

The video transcriber MCP we use is our own code and lives in its own repo: [mapplebox/whisper-video-transcriber](https://github.com/mapplebox/whisper-video-transcriber).

## The common pattern

Every server follows the same setup. The shared files are in [common/](common/).

```
Claude Code (LAN / Tailscale) ──https──> Caddy ──> LXC: MCP server (port 3000/8000)
claude.ai (Anthropic IPs)     ──https──> Caddy ──> LXC: OAuth proxy ──> MCP server
```

1. **One unprivileged LXC per MCP server.** Debian, fixed IP (DHCP reservation). Docker inside needs `nesting=1,keyctl=1` in the container options. If one server misbehaves or gets compromised, it only sees its own secrets.
2. **Docker compose in `/opt/<name>`.** Secrets go into `.env` with `chmod 600`. Only `.env.example` files are in this repo.
3. **Firewall unit on the LXC.** [common/mcp-firewall.service](common/mcp-firewall.service) puts an iptables rule into the `DOCKER-USER` chain, so only the Caddy host can reach the MCP port ([notes](common/README.md)). Ports that Docker publishes skip the normal `INPUT` chain, which is why a plain INPUT rule or ufw does not help here. The Proxmox MCP runs without Docker and uses an nftables rule instead ([proxmox/nftables.conf](proxmox/nftables.conf)).
   The `DOCKER-USER` rule only covers IPv4. That's why every compose file publishes its ports as `0.0.0.0:3000:3000`: with a plain `3000:3000`, Docker also listens on IPv6, and if the LXC has an IPv6 address (common with SLAAC on home networks) the port is reachable over IPv6 without passing the rule. We found exactly that on our own setup. Check with `curl -6 http://[<lxc-ipv6>]:3000/` from another device: it must not answer.
4. **Caddy in front.** Caddy 2.11 from the Debian package plus the [caddy-dns/ionos](https://github.com/caddy-dns/ionos) module (`caddy add-package`) gets certificates through the DNS challenge, so internal names never need to be reachable from the internet. See [common/Caddyfile.snippets](common/Caddyfile.snippets):
   - `(int_only)`: answers 403 to anything outside private ranges and Tailscale (`100.64.0.0/10`).
   - one site per server: `import int_only`, then 401 unless the `Authorization: Bearer <token>` header matches. ProxmoxMCP-Plus checks its own key (`MCP_API_KEY`), so its site only has `int_only`.
5. **Claude Code** adds each server with `claude mcp add --transport http --scope user ... --header "Authorization: Bearer <token>"`. All commands: [common/claude-mcp-add.md](common/claude-mcp-add.md).
6. **Optional public OAuth front door for the claude.ai app.** Custom connectors in claude.ai connect from Anthropic's servers and expect OAuth. For that a server gets a public name and either its own OAuth (WHOOP) or [mcp-auth-proxy](https://github.com/sigbit/mcp-auth-proxy) in front (calendar). Caddy only lets `/mcp` through from Anthropic's outbound range `160.79.104.0/21`. The OAuth login pages stay reachable for your browser and are password protected.

## Placeholders used in this repo

| Placeholder | Meaning |
|---|---|
| `example.com` | your domain. Internal names: `mcp-<x>.int.example.com`, public: `cal.example.com`, `whoop.example.com` |
| `192.168.1.10` | Caddy host |
| `192.168.1.21` to `192.168.1.25` | MCP LXCs (calendar, unifi, paperless, whoop, proxmox) |
| `192.168.1.5` | Proxmox node |
| `192.168.1.30` | Paperless-ngx |
| `CHANGE_ME`, `<...>` | secrets you create yourself |

## Security

- **Nothing internal is public by default.** Proxmox, UniFi and Paperless only answer on LAN and Tailscale, and only with the right Bearer token.
- **Two locks on every internal server:** Caddy checks the IP range and the token (for Proxmox the server checks the token), and the LXC firewall drops every connection that does not come from Caddy. Skipping Caddy by talking to the LXC directly does not work.
- **Public entrances are narrow.** `/mcp` only answers Anthropic's outbound IPs ([source](https://platform.claude.com/docs/en/api/ip-addresses), checked 2026-10-15; Anthropic says these will not change without notice). Login pages need a password.
- **Least privilege per server.** A dedicated Proxmox user and token (PVEAuditor if read only is enough), a local UniFi account, a Paperless user with only the rights Claude needs, an Apple app-specific password that you can revoke on its own.
- **Guard rails in the servers.** ProxmoxMCP-Plus with `command_policy.mode: deny_all` (no shell inside guests). UniFi with `UNIFI_TOOL_PERMISSION_MODE=confirm` and `UNIFI_POLICY_DELETE=false`. Claude takes snapshots before changes and asks before anything disruptive.
- **Secrets never go into chat or git.** `.env`, `auth.env`, `config.json`, keys and certs are in [.gitignore](.gitignore). Create tokens with `openssl rand -hex 32` directly on the server.
- **Tokens are revocable.** Each server has its own token. If one leaks, you replace that one and nothing else.
- **Upstream code is someone else's code.** Pin versions, read changelogs, and check what tools a server exposes before you give it write access.

Found a problem with these recipes? Open an issue. Security problems in a server itself belong to its upstream project.

## License

[MIT](LICENSE) for the files in this repo. The upstream projects have their own licenses.
