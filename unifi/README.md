# UniFi Network MCP

Lets Claude read clients, devices, traffic and alerts from a UniFi Network console, and make changes after you confirm them.
Internal only.

| | |
|---|---|
| Upstream | [sirkirby/unifi-mcp](https://github.com/sirkirby/unifi-mcp) |
| Image | `ghcr.io/sirkirby/unifi-network-mcp:0.20.3` |
| Port | 3000, Streamable HTTP at `/mcp` |
| Auth | Bearer token checked by Caddy |

## Setup

1. Create a **local** UniFi account (UniFi OS > Admins & Users). It must be local, without SSO and without 2FA, or the login from the MCP server fails. Give it only the role you need.
2. LXC with Docker, fixed IP (example `192.168.1.22`).
3. In `/opt/mcp-unifi`:

   ```bash
   cp .env.example .env && cp site.env.example site.env
   chmod 600 .env
   nano .env site.env
   docker compose up -d
   ```

4. Firewall: [../common/mcp-firewall.service](../common/mcp-firewall.service) with `MCP_PORTS=3000`.
5. Caddy block `mcp-unifi.int.example.com` from [../common/Caddyfile.snippets](../common/Caddyfile.snippets).
6. `claude mcp add`, see [../common/claude-mcp-add.md](../common/claude-mcp-add.md).

Several sites: one LXC (or one compose project) per site, each with its own `site.env`, Caddy name and token.

## Safety settings in the compose file

- `UNIFI_TOOL_PERMISSION_MODE=confirm`: every change shows a preview first and needs an explicit confirm.
- `UNIFI_POLICY_DELETE=false`: no delete actions at all. Upstream lets you open single categories with `UNIFI_POLICY_NETWORK_<CATEGORY>_<ACTION>=true` when you really need one.
- `UNIFI_NETWORK_VERIFY_SSL=false` because the console uses a self-signed cert. The traffic stays inside your LAN.
